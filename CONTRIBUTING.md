# Contributing to wolfram-nb-mode

## Getting Started

1. Fork the repository
2. Clone your fork
3. Create a feature branch

## Development Setup

```bash
git clone https://github.com/YOUR-USERNAME/wolfram-nb-mode.git
cd wolfram-nb-mode
```

Load in Emacs:
```elisp
(add-to-list 'load-path "/path/to/wolfram-nb-mode")
(require 'wolfram-nb-mode)
```

## Making Changes

### Code Style

- Follow standard Emacs Lisp conventions
- Use descriptive function names with `wolfram-nb-` prefix
- Private functions use `wolfram-nb--` (double dash)
- Add docstrings to all functions
- Keep lines under 80 characters when possible

### Testing

Always add tests for new features:

```elisp
(ert-deftest wolfram-nb-test-new-feature ()
  "Test description."
  (should (equal (wolfram-nb-new-function "input") "expected")))
```

Run tests before submitting:
```bash
cd tests/
./test-all.sh
```

### Documentation

- Update README.md for user-facing changes
- Update docs/CHANGELOG.md with your changes
- Add docstrings to new functions

## Submitting Changes

1. Run test suite: `cd tests && ./test-all.sh`
2. Update CHANGELOG.md
3. Commit with clear message:
   ```
   Add feature X
   
   - Implement Y
   - Add tests for Z
   - Update documentation
   ```
4. Push to your fork
5. Create Pull Request

## Pull Request Guidelines

- One feature/fix per PR
- Include tests
- Update documentation
- All tests must pass
- Clear commit messages

## Areas for Contribution

- BoxData parsing (extract code from RowBox structures)
- Better Dynamic content handling
- Performance optimizations
- Additional cell type support
- Documentation improvements

## Questions?

Open an issue for discussion before major changes.

## License

By contributing, you agree your contributions will be licensed under MIT License.
