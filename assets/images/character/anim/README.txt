Sprite frames for LiveTrackerAnimation (all 286x512 transparent PNG, frames 01..08):

  anim/<state>/body_<tier>/frame_01.png ... frame_08.png
  anim/<state>/hair_<hairId>/frame_01.png ...
  anim/<state>/gear_<outfitId>/frame_01.png ...

  <state>    idle | walk | jog | run
  <tier>     normal | overweight | obese | underweight
  <hairId>   warrior_spiky | classic_pompadour | wavy_mane | long_flowing | short_crop
  <outfitId> outfit_01

Register every folder you add in pubspec.yaml (Flutter does not recurse), e.g.
  - assets/images/character/anim/run/body_normal/
Missing states fall back to the static layered avatar with a stepped bob.
