/// What to open when the app is launched automatically after a device boot.
enum AutostartAction {
  menu, // just show the menu
  lastChannel, // resume the last watched channel
  category, // play the first channel of a chosen category
  channel, // play a specific chosen channel
}
