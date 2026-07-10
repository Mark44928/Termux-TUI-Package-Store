<p align="center">
   <b>Security Policy</b>
</p>

<p align="center">
   <em>How to report vulnerabilities responsibly.</em>
</p>

---

## Reporting a Vulnerability

If you discover a security vulnerability in Termux TUI Package Store, please report it responsibly.

**Do NOT open a public issue.**

Instead, please email: [your-email@example.com] or open a private security advisory on GitHub.

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

---

## Response Timeline

- **Acknowledgment**: Within 48 hours
- **Initial assessment**: Within 1 week
- **Fix or mitigation**: Within 2 weeks (for confirmed vulnerabilities)

---

## Scope

This project runs `pkg install` and `pkg remove` commands that modify your Termux environment. The following are in scope:

- Command injection through package names or file paths
- Path traversal in backup/export file operations
- Privilege escalation (though the tool runs as a regular Termux user)

---

## Out of Scope

- Issues in upstream dependencies (fzf, pkg, apt-cache)
- Social engineering attacks
- Issues requiring physical access to the device

---

## Best Practices

When using this tool:

- Review package names before confirming installations
- Use the dry-run option (`d`) in batch mode to preview changes
- Avoid running with elevated privileges
- Keep the tool updated to the latest version
