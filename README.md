# SetShifter

A World of Warcraft addon that equips an Equipment Manager set when you change shapeshift form.

For example, you can switch to a feral set when you go into Cat Form and back to your healing set when you return to caster form.

## Installation

1. Download or clone this repository into `World of Warcraft/<flavor>/Interface/AddOns/SetShifter`.
2. Restart the game, or reload the UI with `/reload`.

## Usage

1. Create your gear sets in the Equipment Manager on the character panel.
2. Open **Options → AddOns → SetShifter**, or type `/setshifter`.
3. Pick a set for each form. **Caster** (no form) is a form too. Map it to a set if you want your gear to switch back when you leave a form.

SetShifter equips the set mapped to a form whenever you shift into that form.

### Notes

- **Combat:** armor can't be changed during combat. If you shift while in combat, SetShifter equips the set for your current form as soon as combat ends.
- **Mapped by name:** forms are mapped by their spell name, not their position on the stance bar. Your mappings keep working when talents add or remove forms, such as Moonkin Form.
- **Login:** logging in never swaps your gear.
- **Per character:** each character has its own settings.

## Slash commands

`/sshift` works as a short alias for `/setshifter`.

| Command | Description |
| --- | --- |
| `/setshifter` | Open the settings panel |
| `/setshifter list` | Show which set is mapped to each form |
| `/setshifter equip` | Equip the set for your current form now |
| `/setshifter on` / `off` | Turn automatic swapping on or off |
