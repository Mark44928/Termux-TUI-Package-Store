<p align="center">
   <b>Contributing to Termux TUI Package Store</b>
</p>

<p align="center">
   <em>Thanks for your interest in contributing! Here's how to get started.</em>
</p>

---

## How to Contribute

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/my-feature`)
3. **Commit** your changes (`git commit -m "Add my feature"`)
4. **Push** to the branch (`git push origin feature/my-feature`)
5. **Open** a Pull Request

---

## Development Setup

```bash
git clone https://github.com/YOUR_USERNAME/Termux-TUI-Package-Store.git
cd Termux-TUI-Package-Store
# Requires zsh and fzf — run on a real Termux environment for best results
```

---

## Coding Style

This project is written in **zsh**. Follow these conventions:

- **Always start new scripts with `emulate -L zsh`** to avoid user KSH_ARRAYS/SH_WORD_SPLIT interference.
- Use `print -r --` instead of `echo` for output (avoids interpretation of escape sequences and flags).
- Use `printf "%s" "$var"` instead of `printf "$var"` to prevent format-string issues.
- Quote all variables in double quotes: `"$var"`, not `$var`.
- Use `--` argument separators for dpkg/apt commands: `dpkg -s -- "$pkg"`.
- Internal helper functions use `_pkgs_` prefix. Color variables use `C_` prefix.
- Match the existing if-elif command dispatch pattern in `pkgs()`. If adding a new slash command, add it to the help text and the command list in the README.

---

## Testing

- Run `zsh -n pkgs_core.zsh` to check for syntax errors before committing.
- Test on a **real Termux environment** — the tool relies on Termux-specific paths (`$PREFIX`, `pkg`, `dpkg-query`).
- Test edge cases: empty input, invalid package names, missing dependencies.

---

## Pull Request Guidelines

- Keep changes focused — one feature or fix per PR.
- Update the README and CHANGELOG if adding user-facing changes.
- Run the syntax check before pushing.

---

## Ideas for Contributions

- New package categories or filters
- TUI interface improvements
- Search filter enhancements
- Bug fixes
- Performance optimizations for slow commands

---

## License

By contributing, you agree that your contributions will be licensed under the [MIT License](LICENSE).
