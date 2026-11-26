# CinePulse India — Design System (`DESIGN.md`)

## 1. Visual Philosophy & Aesthetic Direction
- **Theme:** Premium Dark Cinema × Modern Fintech Analytics.
- **Default Mode:** Dark Mode (with full Light Mode parity).
- **Surface Hierarchy (Dark Mode):**
  - Canvas / Background: `#0B0D12` (Obsidian Charcoal — never pure `#000000`)
  - Surface Container Lowest: `#080A0E`
  - Surface Container Low: `#12151E`
  - Surface Container (Primary Card): `#171B26`
  - Surface Container High: `#1F2433`
  - Surface Container Highest: `#272D3F`
  - Subtle Border / Hairline: `1px solid #262C3D`
- **Surface Hierarchy (Light Mode):**
  - Canvas / Background: `#F6F5F0` (Warm Alabaster)
  - Surface Container (Primary Card): `#FFFFFF`
  - Surface Container Low: `#EFEDE6`
  - Subtle Border / Hairline: `1px solid #E0DDD3`
- **Primary Accent (Single Accent Rule, Saturation < 80%):**
  - Burnished Marquee Gold: `#D4A853` (Dark) / `#A67C2E` (Light)
  - Primary Container: `#2D2412` with `#F2D28B` text (Dark)
- **Semantic Status Colors (Data Integrity & Publishing Only):**
  - Verified / Published / Healthy: `#2EC27E` (Emerald)
  - Estimate / Pending Review / Expiring Soon: `#E5A00D` (Warm Amber)
  - Conflict / Failed / Offline: `#E05252` (Crimson)
  - Info / Neutral Tag: `#8B95A8` (Slate)

## 2. Typography
- **Headlines:** `Plus Jakarta Sans` (Weights 600, 700, tight tracking `-0.02em`)
- **Body / UI:** `DM Sans` (Weights 400, 500, 600, crisp legibility on mobile)
- **Numerical / Financial / Box-Office Figures & Timestamps:** `JetBrains Mono` with `tabular-nums` (Weights 500, 600, 700) so `₹142.85 Cr`, `248/280`, and `08:30 IST` align cleanly.

## 3. Shape, Spacing & Elevation
- **Corner Radius:** `8px` (`ROUND_EIGHT`) for cards, inputs, and buttons; `12px` for bottom sheets and confirmation dialogs; `999px` (pill) for language badges, category filter chips, and draft status pills.
- **Spacing Grid:** `4px` base unit (`xs: 4px`, `sm: 8px`, `md: 16px`, `lg: 24px`, `xl: 32px`).
- **Elevation:** Flat-layered tonal contrast + `1px` hairline borders instead of heavy drop shadows. Subtle `0 0 24px rgba(212, 168, 83, 0.08)` glow reserved exclusively for primary CTAs and featured hero metrics.

## 4. Core Reusable Components
- **Collection Amount Display:** Metric label (`INDIA NET`, `INDIA GROSS`, `OVERSEAS`, `WORLDWIDE`) in `10px` uppercase tracked `JetBrains Mono`, followed by `₹XX.XX Cr` in bold tabular monospace, plus a source-status dot (`Estimate`, `Trade Reported`, `Producer Reported`, `Reported Final`). Never mix metrics.
- **Language Badge:** Compact pill (`ML`, `TA`, `TE`, `KN`, `HI`, `BN`, `MR`, `PA`, `GU`) with subtle tonal fill.
- **Draft Status Label:** Pill badge for `PENDING_REVIEW`, `EDITED`, `PUBLISHING`, `PUBLISHED`, `FAILED`, `EXPIRED`.
- **Post Preview Card:** Authentic X-style card with `@handle`, timestamp, formatted post body, source attribution chip, and weighted character counter (`e.g. 214 / 280`).
- **Bottom Navigation:** 4-tab bar (`Home`, `Post Review`, `Movies`, `Settings`) with active gold indicator and pending review badge count.

## 5. Anti-Patterns (Strictly Forbidden)
- No AI purple/cyan neon gradients.
- No pure `#000000` backgrounds.
- No fabricated or placeholder box-office figures in production states (use explicit empty/unavailable states when data is missing).
- No nested cards inside cards beyond 1 level.
