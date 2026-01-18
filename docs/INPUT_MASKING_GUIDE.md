# Input Masking Guide

You can now apply input masks to `text` type questions. This helps surveyors follow a specific format (like barcodes or IDs) and automatically inserts fixed characters like dashes.

## XML Configuration

To add a mask, use the `<mask />` element inside a `<question />`:

```xml
<question type='text' fieldname='fpbarcode1_r21' fieldtype='text'>
    <text>Enter R21 STUDY barcode</text>
    <maxCharacters>=12</maxCharacters>
    <mask value="R21-[0-9][0-9][0-9]-[A-Z0-9][0-9A-Z][A-Z0-9][A-Z0-9]" />
</question>
```

### Mask Syntax

The new syntax uses a "regex-style" approach to avoid ambiguity with literal text.

- **Placeholders**: Wrap any valid regular expression character class in square brackets `[]`. Each pair of brackets represents **exactly one character**.
    - `[0-9]` : Exactly one digit.
    - `[A-Z]` : Exactly one letter.
    - `[A-Z0-9]` : Exactly one alphanumeric character.
- **Literals**: Anything outside of square brackets is treated as literal text.

## Features

1. **Explicit Literals**: You can now safely use any character as literal text. For example, `Part A: [0-9]` will auto-populate `Part A: ` and then wait for a digit.
2. **Auto-population**: If a mask starts with literal characters (like `R21-`), these are automatically filled in when the question loads.
3. **Auto-insertion**: As the user types, literals in the middle (like the second `-`) are automatically inserted.
4. **Uppercase Enforcement**: All input is automatically converted to uppercase.

## Example
**Mask**: `PM:[0-9][0-9]?[A-Z0-9][A-Z0-9][A-Z0-9]`

1. **On Load**: The field displays `PM:`.
2. **Surveyor Types `12`**: The field displays `PM:12?` (the question mark is added automatically).
3. **Surveyor Types `ABC`**: The field displays `PM:12?ABC`.
