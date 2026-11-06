# Skill sources

Where each skill in `.claude/skills/` came from. Claude Code loads these automatically; nobody needs to install them.

Project rules (`AGENTS.md`, the development agreement) win over any skill. To update a skill, copy the new upstream version and change its commit here.

Each folder holds the upstream `SKILL.md` and `references/` unchanged, plus the upstream licence. Left out: plugin packaging (`.claude-plugin/`, nested `skills/` copies), `agents/openai.yaml`, icons in `assets/`, and `evals/`.

| Skill | Source | Commit (date) | Licence | Chosen by |
| --- | --- | --- | --- | --- |
| swiftui-pro | [twostraws/SwiftUI-Agent-Skill](https://github.com/twostraws/SwiftUI-Agent-Skill) | `f2920b6` (Oct 26, 2026) | MIT | Mas Bowo |
| swiftdata-pro | [twostraws/SwiftData-Agent-Skill](https://github.com/twostraws/SwiftData-Agent-Skill) | `8051f17` (Oct 19, 2026) | MIT | Mas Bowo |
| coreml | [dpearson2699/swift-ios-skills](https://github.com/dpearson2699/swift-ios-skills) | `8d90fd1` (Jul 31, 2026) | PolyForm Perimeter 1.0.0 | Mas Bowo |
| ios-accessibility | [dadederk/iOS-Accessibility-Agent-Skill](https://github.com/dadederk/iOS-Accessibility-Agent-Skill) | `dcc3a36` (Mar 9, 2026) | MIT | Mas Bowo |
| swift-concurrency-pro | [twostraws/Swift-Concurrency-Agent-Skill](https://github.com/twostraws/Swift-Concurrency-Agent-Skill) | `bee3f69` (May 17, 2026) | MIT | Amadeus |
| swiftlint | [dpearson2699/swift-ios-skills](https://github.com/dpearson2699/swift-ios-skills) | `8d90fd1` (Jul 31, 2026) | PolyForm Perimeter 1.0.0 | Amadeus |
| debugging-instruments | [dpearson2699/swift-ios-skills](https://github.com/dpearson2699/swift-ios-skills) | `8d90fd1` (Jul 31, 2026) | PolyForm Perimeter 1.0.0 | Amadeus |
| test-driven-development | [obra/superpowers](https://github.com/obra/superpowers) | `22f0b46` (Nov 3, 2026) | MIT | Amadeus |

The PolyForm licence requires keeping its terms and the `Required Notice:` line with every copy; both are in each of those skills' `LICENSE` files.

All commits were the newest on each repo's default branch when checked on November 6, 2026.
