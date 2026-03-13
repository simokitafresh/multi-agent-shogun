# Shogun Android App — Design System

## Direction
Sengoku command post — a warlord's war room brought to mobile.
Dark, authoritative, gold-accented. Every screen feels like looking down from a castle tower at your army below.

## Feel
Dense like a military command center. Warm like firelight in a castle. Authoritative like a shogun's decree.

## Domain Concepts
- Castle tower (tenshu) overlooking battlefield
- Scroll and ink brush — commands written in calligraphy
- Lacquered armor — black base with gold ornament
- War camp curtains (jinmaku) and bonfires
- War fan (gunbai) — the tool of command

## Color Palette

### Primitives
| Token | Hex | Role | Origin |
|-------|-----|------|--------|
| `--shikkoku` | #1A1A1A | Base background | Lacquered armor base |
| `--sumi` | #2D2D2D | Elevated surface | Ink stone, castle wall |
| `--kinpaku` | #C9A94E | Primary text, accents | Gold leaf on shrine |
| `--zouge` | #E8DCC8 | Body text | Washi paper, scroll |
| `--shuaka` | #B33B24 | Action, CTA, destructive | Vermilion torii gate |
| `--matsuba` | #3C6E47 | Success, connected | Pine garden |
| `--tetsukon` | #3A4A5C | Secondary, metadata | Iron armor plate |
| `--kurenai` | #CC3333 | Error, disconnected | Blood red |

### Theme Modes
| Mode | Background | Surface | Body Text | Accent Gold | Accent Red | Mood |
|------|------------|---------|-----------|-------------|------------|------|
| Dark | `#1A1A1A` | `#2D2D2D` | `#E8DCC8` | `#C9A94E` | `#B33B24` | 現行の漆黒。篝火と甲冑の war room |
| Light | `#F5EFE3` | `#FFF9F0` | `#332A22` | `#7A5A16` | `#9B3A2A` | 白壁の城、書院造り。明所でも文字が沈まない |
| Black AMOLED | `#000000` | `#0A0A0A` | `#F5F1E8` | `#D4B96A` | `#C24A33` | 真夜中の陣。OLED省電力と最大コントラスト |

### Theme Surface Stack
| Mode | Base | Card | Raised | Overlay | Input |
|------|------|------|--------|---------|-------|
| Dark | `#1A1A1A` | `#2D2D2D` | `#363636` | `#404040` | `#1E1E1E` |
| Light | `#F5EFE3` | `#FFF9F0` | `#E9DDCA` | `#E0D2BE` | `#F8F1E6` |
| Black AMOLED | `#000000` | `#0A0A0A` | `#141414` | `#1D1D1D` | `#101010` |

### Accessibility Guardrails
- Light mode本文 `#332A22` on `#F5EFE3` = 12.27:1
- Light mode見出し金 `#7A5A16` on `#F5EFE3` = 5.55:1
- Black mode本文 `#F5F1E8` on `#000000` = 18.63:1
- 純黒テキストは使わない。ライト mode の濃色文字は `#332A22` を基準にする

### Text Hierarchy
| Level | Color | Use |
|-------|-------|-----|
| Primary | `--kinpaku` #C9A94E | Headings, agent names, tab labels |
| Secondary | `--zouge` #E8DCC8 | Body text, terminal output |
| Tertiary | `--tetsukon` #8A9BB0 (lightened) | Metadata, timestamps |
| Muted | #666666 | Disabled, placeholders |

### Surface Elevation
| Level | Color | Use |
|-------|-------|-----|
| 0 (base) | #1A1A1A | Screen background |
| 1 (card) | #2D2D2D | Cards, pane tiles |
| 2 (raised) | #363636 | Dropdowns, dialogs |
| 3 (overlay) | #404040 | Modals, fullscreen overlays |

## Depth Strategy
**Borders-only** — subtle gold borders at low opacity. No shadows. Dense military tool aesthetic.
- Standard border: `#C9A94E` at 20% opacity
- Emphasis border: `#C9A94E` at 40% opacity
- Focus ring: `#C9A94E` at 60% opacity

## Spacing
Base unit: 8dp
- Micro: 4dp (icon gaps)
- Component: 8dp (within cards)
- Section: 16dp (between groups)
- Major: 24dp (between screen sections)

## Border Radius
- Buttons/Inputs: 4dp (sharp, military)
- Cards: 6dp (slightly softened)
- No large radius anywhere — this is a war room, not a toy

## Typography
- Terminal output: Monospace (system default)
- UI labels: System sans-serif, medium weight
- Agent names: Monospace, gold color
- Tab labels: Medium weight, ALL CAPS optional for gravitas

## Signature Element
**Jinmaku bar (陣幕バー)** — the top status bar spans full width like war camp curtains:
- Connected: Matsuba green (#3C6E47) with subtle texture
- Disconnected: Kurenai red (#CC3333)
- Reconnecting: Kinpaku gold (#C9A94E) pulsing

## Component Patterns

### Tab Bar (Bottom Navigation)
- Background: #1A1A1A (same as base — no separation)
- Separator: thin gold line at top (#C9A94E at 20%)
- Active icon/label: Kinpaku gold
- Inactive icon/label: #666666
- Labels: 将軍 / 陣形 / 軍配 / 設定

### Pane Card (Agent Grid)
- Background: Sumi #2D2D2D
- Border: Kinpaku at 20% opacity
- Agent name: Kinpaku gold, monospace
- Content: Zouge ivory, monospace 10sp
- Tap → fullscreen transition (no dialog)

### Input Field
- Background: #1E1E1E (inset, darker than surroundings)
- Border: #C9A94E at 20%
- Focus border: #C9A94E at 60%
- Text: Zouge ivory
- Placeholder: #666666

### Buttons
- Primary: Shuaka red background, white text, 4dp radius
- Secondary: Transparent, Kinpaku text, Kinpaku border at 30%
- Disabled: #333333 background, #666666 text

### Dashboard (Markdown)
- Background: Shikkoku #1A1A1A
- Text: Zouge ivory #E8DCC8
- Headings: Kinpaku gold
- Links: lighter gold #D4B96A
- Table borders: Kinpaku at 20%
- Code blocks: Sumi #2D2D2D background

## Avoid
- Pure white anything
- Material3 purple/blue defaults
- Rounded corners > 8dp
- Colorful gradients
- Drop shadows
- Bright saturated colors
