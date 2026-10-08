import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../services/friends_service.dart';
import '../../utils/chat_filter.dart';
import '../../widgets/block_ui.dart';

/// Private 1:1 text chat with a friend.
class ChatScreen extends StatefulWidget {
  final String friendUid;
  final String friendName;
  const ChatScreen({super.key, required this.friendUid, required this.friendName});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctl = TextEditingController();
  final _scroll = ScrollController();
  late final String _me;
  bool _sending = false;
  DateTime _lastSent = DateTime.fromMillisecondsSinceEpoch(0);
  List<String> _recent = []; // newest-first texts, attached to a report as evidence

  // quick cheers for mid-challenge banter
  static const _quick = ['\u{1F525} Let\'s go!', '\u{1F44F} Nice run!', '\u{1F3C3} On my way', '\u{1F4AA} Rematch?'];

  @override
  void initState() {
    super.initState();
    _me = FirebaseAuth.instance.currentUser?.uid ?? '';
    FriendsService.markRead(_me, widget.friendUid);
  }

  @override
  void dispose() {
    FriendsService.markRead(_me, widget.friendUid);
    _ctl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    var text = (preset ?? _ctl.text).trim();
    if (text.isEmpty || _sending || _me.isEmpty) return;

    final problem = ChatFilter.blockReason(text);
    if (problem != null) {
      _notice('Message not sent', problem);
      return;
    }
    if (DateTime.now().difference(_lastSent) < ChatFilter.minGap) {
      _notice('Slow down', 'You are sending messages too fast.');
      return;
    }
    final masked = ChatFilter.hasProfanity(text);
    text = ChatFilter.clean(text);

    setState(() => _sending = true);
    try {
      _lastSent = DateTime.now();
      await FriendsService.sendMessage(me: _me, other: widget.friendUid, text: text);
      if (masked && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Some words were hidden. Please keep chat friendly.')));
      }
      if (preset == null) _ctl.clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not send. Are you still friends?')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ───────────────────────── safety ─────────────────────────

  /// Centered notice (not a bottom snackbar).
  Future<void> _notice(String title, String body) => showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.transparent,
          child: Block(
            color: Rb.slate,
            edge: Colors.black,
            depth: 6,
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                BlockText(title, size: 16, stroke: 4, color: Rb.gold),
                const SizedBox(height: 6),
                BlockText(body, size: 12, stroke: 3, align: TextAlign.center),
                const SizedBox(height: 14),
                PressBlock(
                  color: Rb.green,
                  edge: Rb.greenEdge,
                  depth: 5,
                  radius: 12,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  onTap: () => Navigator.of(ctx).pop(),
                  child: const SizedBox(
                    width: double.infinity,
                    child: Center(child: BlockText('OK', size: 14, stroke: 3.5)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  static const _reasons = [
    'Harassment or bullying',
    'Inappropriate language',
    'Spam or links',
    'Cheating in duels',
    'Other',
  ];

  Future<void> _reportDialog() async {
    var reason = _reasons.first;
    final noteCtl = TextEditingController();
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Block(
            color: Rb.slate,
            edge: Colors.black,
            depth: 8,
            radius: 20,
            padding: const EdgeInsets.all(14),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  BlockText('\u2691 REPORT ${widget.friendName}'.toUpperCase(),
                      size: 15, stroke: 4, color: Rb.orange, align: TextAlign.center),
                  const SizedBox(height: 4),
                  const BlockText('The last few messages are sent with your report so it can be reviewed.',
                      size: 10, stroke: 2.5, align: TextAlign.center,
                      color: Color(0xFFB8BDC4)),
                  const SizedBox(height: 10),
                  for (final r in _reasons)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: PressBlock(
                        color: reason == r ? Rb.orange : Rb.panel,
                        edge: reason == r ? Rb.orangeEdge : Rb.panelEdge,
                        depth: 3,
                        radius: 10,
                        forcePressed: reason == r,
                        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
                        onTap: () => setS(() => reason = r),
                        child: SizedBox(
                          width: double.infinity,
                          child: BlockText(r, size: 11.5, stroke: 3),
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: Rb.panel,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black, width: 3),
                    ),
                    child: TextField(
                      controller: noteCtl,
                      maxLines: 2,
                      maxLength: 300,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        counterText: '',
                        hintText: 'Add details (optional)',
                        hintStyle: TextStyle(color: Colors.white38, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: PressBlock(
                          color: Rb.panel,
                          edge: Rb.panelEdge,
                          depth: 4,
                          radius: 12,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          onTap: () => Navigator.of(ctx).pop(false),
                          child: const Center(child: BlockText('CANCEL', size: 12, stroke: 3.5)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: PressBlock(
                          color: Rb.red,
                          edge: Rb.redEdge,
                          depth: 4,
                          radius: 12,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          onTap: () => Navigator.of(ctx).pop(true),
                          child: const Center(child: BlockText('SEND REPORT', size: 12, stroke: 3.5)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final note = noteCtl.text.trim();
    noteCtl.dispose();
    if (send != true || !mounted) return;
    try {
      await FriendsService.report(
        me: _me,
        reported: widget.friendUid,
        reportedName: widget.friendName,
        reason: reason,
        note: note,
        recent: _recent,
      );
      if (mounted) {
        await _notice('Report sent', 'Thank you. You can also block this player with the \u26D4 button.');
      }
    } catch (_) {
      if (mounted) await _notice('Could not send', 'Please try again in a moment.');
    }
  }

  Future<void> _blockDialog() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Block(
          color: Rb.slate,
          edge: Colors.black,
          depth: 6,
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              BlockText('Block ${widget.friendName}?', size: 16, stroke: 4, align: TextAlign.center),
              const SizedBox(height: 6),
              const BlockText(
                  'They are removed from your friends and can no longer find you with your code.',
                  size: 11, stroke: 3, align: TextAlign.center),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: PressBlock(
                      color: Rb.blue,
                      edge: Rb.blueEdge,
                      depth: 5,
                      radius: 12,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      onTap: () => Navigator.of(ctx).pop(false),
                      child: const Center(child: BlockText('CANCEL', size: 13, stroke: 3.5)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: PressBlock(
                      color: Rb.red,
                      edge: Rb.redEdge,
                      depth: 5,
                      radius: 12,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      onTap: () => Navigator.of(ctx).pop(true),
                      child: const Center(child: BlockText('BLOCK', size: 13, stroke: 3.5)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await FriendsService.block(_me, widget.friendUid);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) await _notice('Could not block', 'Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = FriendsService.chatId(_me, widget.friendUid);
    return Scaffold(
      backgroundColor: Rb.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Block(
                color: Rb.hud,
                edge: Rb.hudEdge,
                depth: 5,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  children: [
                    PressBlock(
                      color: Rb.red,
                      edge: Rb.redEdge,
                      depth: 4,
                      radius: 10,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const BlockText('◀', size: 14, stroke: 3.5),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: BlockText('\u{1F4AC} ${widget.friendName}', size: 18, stroke: 4),
                      ),
                    ),
                    const SizedBox(width: 6),
                    PressBlock(
                      color: Rb.orange,
                      edge: Rb.orangeEdge,
                      depth: 3,
                      radius: 10,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      onTap: _reportDialog,
                      child: const BlockText('\u2691 REPORT', size: 10, stroke: 3),
                    ),
                    const SizedBox(width: 6),
                    PressBlock(
                      color: Rb.slot,
                      edge: Rb.slateEdge,
                      depth: 3,
                      radius: 10,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      onTap: _blockDialog,
                      child: const BlockText('\u26D4', size: 12, stroke: 3),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: FriendsService.chats
                    .doc(id)
                    .collection('messages')
                    .orderBy('ts', descending: true)
                    .limit(100)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const Center(
                      child: BlockText('Chat is unavailable.\nAre you still friends?',
                          size: 12, stroke: 3, align: TextAlign.center),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: Rb.green));
                  }
                  final docs = snap.data!.docs;
                  _recent = docs.map((d) => (d.data()['text'] as String?) ?? '').toList();
                  if (docs.isEmpty) {
                    return const Center(
                      child: BlockText('Say hi \u{1F44B}', size: 14, stroke: 3.5),
                    );
                  }
                  // we are looking at it right now
                  FriendsService.markRead(_me, widget.friendUid);
                  return ListView.builder(
                    controller: _scroll,
                    reverse: true, // newest at the bottom
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final m = docs[i].data();
                      return _bubble(m['text'] as String? ?? '', m['from'] == _me);
                    },
                  );
                },
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  for (final q in _quick)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 4),
                      child: PressBlock(
                        color: Rb.slot,
                        edge: Rb.slateEdge,
                        depth: 3,
                        radius: 14,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        onTap: () => _send(q),
                        child: BlockText(q, size: 11, stroke: 3),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: Rb.panel,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.black, width: 3),
                      ),
                      child: TextField(
                        controller: _ctl,
                        maxLength: FriendsService.maxMessage,
                        onSubmitted: (_) => _send(),
                        textInputAction: TextInputAction.send,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                        cursorColor: Rb.neon,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          counterText: '',
                          hintText: 'Message',
                          hintStyle: TextStyle(color: Colors.white38, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PressBlock(
                    color: Rb.green,
                    edge: Rb.greenEdge,
                    depth: 5,
                    radius: 20,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    onTap: _sending ? null : _send,
                    child: const BlockText('SEND', size: 13, stroke: 3.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bubble(String text, bool mine) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Block(
            color: mine ? const Color(0xFF1E5F8F) : Rb.slate,
            edge: mine ? const Color(0xFF0A2B45) : Rb.slateEdge,
            depth: 3,
            radius: 14,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(
              text,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14, height: 1.25),
            ),
          ),
        ),
      ),
    );
  }
}
