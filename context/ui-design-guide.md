# UI Design Guide
<!-- last_updated: 2026-04-16 cmd_1937 -->
Readers: agents. Keep this as an index layer. Use linked sources for deeper detail.

## §1. Unified Index

Source legend:
- `14-n`: https://www.adhamdannaway.com/blog/ui-design/ui-design-tips-14
- `16-n`: https://www.adhamdannaway.com/blog/ui-design/ui-design-tips
- `BTN`: https://www.adhamdannaway.com/blog/ui-design/button-design-tips

| Principle | Sources | Operational rule |
|---|---|---|
| Group related elements with space | 14-1, 16-1 | Increase internal spacing inside a group and larger spacing between groups. Do not rely on borders first. |
| Keep patterns consistent | 14-12, 16-2 | Reuse the same spacing, icon treatment, radius, elevation, and interaction pattern for the same job. |
| Similar look must mean similar behavior | 16-3, BTN | If two elements look alike, users will assume the same interaction. Different jobs need visibly different treatments. |
| Run a Squint Test on hierarchy | 16-4 | Blur or squint at the screen. The primary action, supporting content, and metadata should still separate into a clear order. |
| Build a clear visual hierarchy | 16-4 | Importance must be obvious when squinting: primary action first, then supporting content, then metadata. |
| Use one obvious primary action | 14-3, 16-4, BTN | A screen should rarely have multiple competing primary buttons. One action gets the strongest fill/contrast. |
| Remove unnecessary styles | 16-5 | Delete decorative borders, fills, shadows, and colors that do not add meaning, grouping, or affordance. |
| Remove unnecessary containers | 14-10, 16-5 | If spacing already groups content, avoid extra cards, frames, or boxes that add noise without structure. |
| Do not confuse minimal with simple | 14-13, 16-5 | Simplicity is clarity, not absence. Keep the cues users need even if the layout becomes less minimal. |
| Keep important content visible | 14-5 | Key actions, prices, status, and next steps should be visible without hunting, hidden tabs, or ambiguous truncation. |
| Use color purposefully | 16-6 | Start from black/white/gray, then add color where it signals interaction, status, or emphasis. |
| Do not rely on color alone | 14-7, 16-9, BTN | Add underline, icon, label, weight, or position so meaning survives grayscale and color blindness. |
| Interface elements need 3:1 contrast | 14-2, 16-7, BTN | Buttons, inputs, icons, toggles, and outlines must be distinguishable as interface elements at 3:1 or higher. |
| Small text needs 4.5:1 contrast | 14-9, 16-8, BTN | Text at 18px and under should meet 4.5:1. Large or bold text can drop to 3:1 only when WCAG allows it. |
| Buttons need large hit areas | 14-4, BTN | Keep touch targets at 48pt x 48pt minimum and leave enough space between adjacent actions. |
| Large headings need tighter tracking | 14-6 | Oversized type usually needs reduced letter spacing to avoid a scattered, unstable look. |
| Use a single sans serif typeface by default | 16-10 | Prefer one neutral sans serif family for UI. Add extra families only with a clear role and compatibility. |
| Prefer high x-height typefaces for small text | 16-11 | Use fonts with taller lowercase letters and decent spacing for labels, body text, and dense UI. |
| Limit uppercase | 16-12 | Reserve all caps for short labels only. Sentence case is the default for readability. |
| Use regular and bold weights only | 14-11, 16-13 | Keep the type scale simple. Regular for body/supporting text, bold for headings and emphasis. |
| Avoid pure black body text on white | 16-14 | Use dark gray instead of pure black to reduce glare and keep hierarchy easier to tune. |
| Keep body text left aligned | 14-8, 16-15 | Avoid mixed alignments. Use left alignment for long text; center only short headings or tiny labels. |
| Use 1.5+ line height for body text | 16-16 | Default body copy to 1.5-2.0 line height, especially for longer paragraphs and dense settings screens. |
| Balance icon and text pairs | 14-14 | Icon and label should feel like one unit: matched size, spacing, and vertical alignment. |
| Button weights must differ without color alone | BTN | Safe baseline: primary=high contrast fill, secondary=high contrast outline, tertiary=underlined text. |
| Use the same button shape for the same job | 16-3, BTN | Do not change only one button into a pill, rounded chip, or odd silhouette unless behavior also changes. |

## §2. First-Pass Review Checklist

| Area | Binary check |
|---|---|
| Grouping | Can a reviewer identify groups from spacing alone before reading labels? |
| Hierarchy | Is the main action the most prominent item when the screen is blurred or squinted at? |
| Visibility | Are the next step, current status, and critical context visible without extra interaction? |
| Color | If all color is removed, do links, buttons, states, and priority still remain understandable? |
| Typography | Are body text, labels, and headings readable at a glance without decorative friction? |
| Buttons | Do primary, secondary, and tertiary actions remain distinguishable in grayscale? |

## §3. Accessibility Floors

| Item | Floor | Note |
|---|---|---|
| UI element contrast | 3:1 | Applies to buttons, inputs, icons, borders, and other interactive shapes. |
| Small text contrast | 4.5:1 | Use for text at 18px and under. |
| Large text contrast | 3:1 | Allowed only for bold 18px+ or regular 24px+ text. |
| Touch target | 48pt x 48pt | Treat as a minimum, not a goal. |
| Body line height | 1.5-2.0 | Default toward readability unless a proven dense layout requires tighter leading. |

## §4. Typography Defaults

| Topic | Default |
|---|---|
| Typeface count | One sans serif family for most UI |
| Font weights | Regular + bold only |
| Case | Sentence case by default |
| Tracking | Tighten large display text; keep body tracking neutral |
| Body color | Dark gray, not pure black |
| Alignment | Left align body copy and data-heavy text |
| Long text leading | 1.5 or more |

## §5. Layout and Simplicity Rules

| Rule | Why |
|---|---|
| Space is the first grouping tool | It clarifies structure before decoration. |
| Borders are optional, not default | Containers add noise when spacing already solves grouping. |
| Minimalism is not the goal | Clarity is the goal. Remove noise, not guidance. |
| Critical information stays in view | Hidden priority content creates friction and weakens confidence. |
| Mixed alignment is a smell | It often signals ad hoc composition rather than a system. |
| Buttons need a 3-step emphasis system | Use filled, outlined, and underlined treatments in descending priority. Do not use gray buttons to fake hierarchy. Keep adjacent actions at least 16pt apart and keep each button treatment distinguishable at 3:1 contrast or higher. |

## §6. Color and Affordance Rules

| Rule | Default action |
|---|---|
| Color carries meaning, not decoration | Reserve accent colors for interaction, status, or emphasis. |
| Non-interactive elements should not mimic links | Remove accent color when an element does not do anything. |
| Links need more than color | Underline or otherwise differentiate them from plain text. |
| Interactive shapes must stay visible on any background | Add fill, outline, or contrast-safe backing when overlays sit on images. |

## §7. Button System Safe Defaults

| Weight | Visual treatment | Use case |
|---|---|---|
| Primary | High-contrast filled button | Most important action on the screen |
| Secondary | High-contrast outline, no fill | Alternate action with clear but lower emphasis |
| Tertiary | Underlined text button | Optional, destructive-light, or low-emphasis action |

Avoid these failure patterns:
- Two filled buttons with similar contrast competing for priority.
- Text-only tertiary actions that depend on color alone.
- Secondary and tertiary buttons separated only by slight gray shifts.
- Inconsistent button shapes for actions with identical behavior.

## §8. Source Map

| Source | Scope | Use it for |
|---|---|---|
| `14 rules` | Broad logic-driven UI cleanup | Visibility, spacing, button priority, tracking, consistency, icons |
| `16 tips` | Example-based interface cleanup | Hierarchy, typography, color use, contrast, readability |
| `button design tips` | Action hierarchy and accessibility | Primary/secondary/tertiary system, contrast, target size, safe button patterns. URL: https://www.adhamdannaway.com/blog/ui-design/button-design-tips |

Related repo pointers:
- `context/doc-style-guide.md`
- `context/neo-design-exploration.md`
- `CLAUDE.md` Cross-Project Context
