# Third-party skills vendored under `.github/skills/`

The following skill directories were copied verbatim from
[github/awesome-copilot](https://github.com/github/awesome-copilot) and are
redistributed under the MIT License reproduced below. The only local edits are a
`Source:` line placed directly after the YAML frontmatter of each `SKILL.md` and
an appended section titled「在 Cheshire 仓库中的使用说明」. The upstream text itself
is unchanged.

| Directory | Upstream path | Files |
| --- | --- | --- |
| `test-gap-audit/` | `skills/test-gap-audit/` | `SKILL.md`, `scripts/coverage_map.py` |
| `breakdown-test/` | `skills/breakdown-test/` | `SKILL.md` |
| `create-implementation-plan/` | `skills/create-implementation-plan/` | `SKILL.md` |

`test-gap-audit/scripts/coverage_map.py` keeps its upstream header and is therefore
excluded from the repository licence-header check in `.github/workflows/lint.yml`.

All other directories under `.github/skills/` (`cheshire-*`, `sv-assertions-coverage`)
are original work of DV365 Lab and follow the repository `LICENSE`.

## MIT License (github/awesome-copilot)

```text
MIT License

Copyright GitHub, Inc.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
