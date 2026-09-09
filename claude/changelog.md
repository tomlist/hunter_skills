# Changelog Skill

Create or update `doc/changelog.txt` from git commit history.

## Usage

```
/changelog [branch] [since]
```

- `branch`: Git branch to generate changelog from. Defaults to current branch.
- `since`: Only include commits after this date (YYYY-MM-DD). Defaults to last entry in existing changelog, or all commits.

## Behavior

### If `doc/changelog.txt` does not exist
1. Use the specified branch (or current branch if not specified).
2. Get all commits from that branch: `git log <branch> --reverse --date=iso --format="%h %ad %an: %s" --name-only`
3. Group commits by **date + author**. Same author on same day → single entry.
4. Skip merge commits that have no file changes (no `--name-only` output beyond the commit message).
5. Format each entry as:
   ```
   YYYY-MM-DD  author — summary description
     + path/to/file1 (brief description if not obvious)
     + path/to/file2
     - path/to/deleted_file
     M path/to/modified_file
   ```
6. Write to `doc/changelog.txt`, newest entries first (reverse chronological order).

### If `doc/changelog.txt` already exists
1. Parse the latest date from the existing file.
2. Only add commits newer than that date.
3. If `since` is specified, use that date instead.
4. Prepend new entries to the top of the file (newest first).
5. Do NOT modify existing entries.

## Rules

- **File detail**: Every entry must list the specific files added (`+`), deleted (`-`), or modified (`M`).
- **Skip empty merges**: Merge commits that change no files are excluded.
- **Group by day+author**: Multiple commits by the same person on the same day are merged into one entry.
- **Reverse chronological**: Newest entries at the top.
- **Output path**: Always `doc/changelog.txt` relative to repo root.
- **Branch scope**: Use `git log <branch>` to get commits. The branch history includes merge commits from other branches that were merged into it.
