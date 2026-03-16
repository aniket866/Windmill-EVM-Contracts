### Addressed Issues:
<!-- Link the issue this PR addresses -->
Fixes #(TODO: issue number)

### Summary:
<!-- Explain what changed and why -->

### Contract Scope:
<!-- List affected contracts/libraries/scripts/tests -->

### Security Considerations:
<!-- Note trust assumptions, auth model changes, and new attack surfaces -->

### Storage/Layout Impact:
<!-- Required for upgradeable patterns and ABI/storage compatibility -->
- [ ] No storage layout changes
- [ ] Storage layout changed (explain below)

### Gas and Performance:
<!-- Mention expected gas impact and include notable changes -->

### Test Evidence:
<!-- Paste short output snippets or links to CI runs -->
- `forge fmt --check`:
- `forge build --sizes`:
- `forge test -vvv`:
- `forge coverage`:
- `forge snapshot`:

### Deployment and Verification:
<!-- Describe script/network/env changes and explorer verification status -->
- [ ] Requires deployment script updates
- [ ] Requires env/config updates (`PRIVATE_KEY`, RPC URL, explorer key)
- [ ] Requires explorer verification updates
- [ ] No deployment impact

### Screenshots/Recordings:
<!-- If applicable, add screenshots or recordings to demonstrate the changes -->

### Additional Notes:
<!-- Add any additional information, context, or notes for reviewers -->

## Checklist
<!-- Mark items with [x] to indicate completion -->
- [ ] My PR addresses a single issue, fixes a single bug or makes a single improvement.
- [ ] My code follows the project's code style and conventions.
- [ ] If applicable, I have made corresponding changes or additions to the documentation.
- [ ] If applicable, I have made corresponding changes or additions to tests.
- [ ] My changes generate no new warnings or errors.
- [ ] I have joined the Stability Nexus's [Discord server](https://discord.gg/eqYhuFzuKN) and I will share a link to this PR with the project maintainers there.
- [ ] I have read the [Contribution Guidelines](CONTRIBUTING.md).
- [ ] Once I submit my PR, CodeRabbit AI will automatically review it and I will address CodeRabbit's comments.
- [ ] I reviewed contract access control and authorization paths.
- [ ] I reviewed reentrancy/external-call ordering where relevant.
- [ ] I confirmed storage compatibility (or documented intentional breakage).
- [ ] I reviewed gas impact for hot paths.

## AI Usage Disclosure

Check one of the checkboxes below:

- [ ] This PR does not contain AI-generated code at all.
- [ ] This PR contains AI-generated code. I have tested the code locally and I am responsible for it.

I have used the following AI models and tools: TODO

### AI Notice - Important!

We encourage contributors to use AI tools responsibly when creating Pull Requests. While AI can be a valuable aid, it is essential to ensure that your contributions meet the task requirements, build successfully, include relevant tests, and pass all linters. Submissions that do not meet these standards may be closed without warning to maintain the quality and integrity of the project. Please take the time to understand the changes you are proposing and their impact.
