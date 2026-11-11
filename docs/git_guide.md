# Git guide for the team

Short, practical guide. Run commands in the VSCode terminal (*Terminal -> New Terminal*) at the project root.
Replace `feature/your-name` with your own branch name, e.g. `feature/an`.

## The 6-step loop (do this every time)

```bash
git checkout main            # 1. go to main
git pull                     # 2. get the latest work from everyone
git checkout -b feature/your-name-task   # 3. create your branch (first time) 
# ... edit files in Godot / VSCode ...
git add .                    # 4. stage your changes
git commit -m "Add design screen layout"  # 5. save a snapshot
git push -u origin feature/your-name-task # 6. upload; then open a Pull Request on GitHub
```

After the first push of a branch, later pushes are just `git push`.

## Key ideas

- **Repository (repo):** the project folder tracked by git.
- **Branch:** your own copy of the timeline. Work on your branch, never directly on `main`.
- **Commit:** a saved snapshot with a message. Small and frequent is better.
- **Push:** send your commits to GitHub. **Pull:** download others' commits.
- **Pull Request (PR):** a request to merge your branch into `main`, so others can review it.

## Command reference

### Look around (safe, run any time)

| Command | What it does |
|---|---|
| `git status` | Shows which files changed and which branch you are on |
| `git branch` | Lists local branches (`*` marks the current one) |
| `git log --oneline -10` | Last 10 commits |
| `git diff` | Shows unstaged changes line by line |

### Branches

```bash
git checkout -b feature/your-name-task   # create AND switch to a new branch
git checkout main                        # switch to an existing branch
git branch                               # which branch am I on?
```

Branch naming: `feature/<name>-<short-task>`, e.g. `feature/an-design-screen`. Keep branches short-lived (a few hours), then merge and start a new one.

### Save your work

```bash
git status                       # check what changed
git add .                        # stage everything
git add scenes/design/           # or stage only one folder/file
git commit -m "Short clear message"
```

Good messages: `Add rocket selection cards`, `Fix budget not updating`. Bad: `update`, `fix`, `asdf`.

Before `git add .`, run `git status` and make sure you only see files from **your own folders** (see `docs/roles.md`). If you see files you did not mean to change, add specific paths instead of `.`.

### Share and receive

```bash
git push -u origin feature/your-name-task   # first push of a new branch
git push                                     # later pushes on the same branch
git pull                                     # update the current branch from GitHub
```

### Pull Request (on GitHub)

1. Push your branch.
2. Open the repo on GitHub. A yellow banner "Compare & pull request" appears; click it. (Or go to *Pull requests -> New pull request*.)
3. Base: `main`. Compare: your branch.
4. Write a title and 1-3 lines about what changed. Click **Create pull request**.
5. Ask the Tech Lead (or a teammate) to review. After approval click **Merge pull request**.
6. Back in the terminal, update your machine:

```bash
git checkout main
git pull
git checkout -b feature/your-name-next-task    # start fresh for the next task
```

## Keep your branch up to date

If `main` moved while you were working, bring it into your branch:

```bash
git checkout main
git pull
git checkout feature/your-name-task
git merge main
```

Do this at least once before opening a PR. It is much easier to fix problems in small steps.

## Merge conflicts

A conflict happens when two people edit the same lines of the same file. Git stops and marks the file:

```
<<<<<<< HEAD
your version
=======
their version
>>>>>>> main
```

1. Open the file in VSCode. It shows buttons: *Accept Current*, *Accept Incoming*, *Accept Both*.
2. Choose the correct result and delete the `<<<<<<<`, `=======`, `>>>>>>>` lines.
3. Then:

```bash
git add <the-fixed-file>
git commit        # finishes the merge
```

**For `.tscn` (scene) files:** do not try to merge by hand. Ask the Tech Lead. Avoid the problem by only editing scenes you own.

## Undo things (safe options first)

| Situation | Command |
|---|---|
| Discard unsaved changes in one file | `git restore path/to/file` (**cannot be undone**) |
| Unstage a file you added by mistake | `git restore --staged path/to/file` |
| Fix the message of your **last** commit (not pushed yet) | `git commit --amend -m "New message"` |
| Undo the last commit but keep the changes | `git reset --soft HEAD~1` |
| Committed to `main` by mistake (not pushed) | Ask the Tech Lead before doing anything |

Avoid these unless the Tech Lead says so: `git push --force`, `git reset --hard`, `git clean -f`. They can destroy teammates' work. They are also blocked in `.claude/settings.json` for Claude.

## Rules of thumb

- `git pull` **before** you start working and before you push.
- Commit small and often. Push at least when you finish a task.
- Never work directly on `main`.
- Only commit files in your own folders. Never edit someone else's scene.
- Do not commit machine-specific files (e.g. `.vscode/`, `.godot/`). `.godot/` is already ignored.
- Commit a script and its `.uid` file together. Never delete a `.uid` file.
- If something looks wrong or scary, **stop and ask** instead of trying random commands.

## Troubleshooting

| Message | Meaning and fix |
|---|---|
| `Your local changes would be overwritten by checkout/merge` | You have unsaved changes. Commit them first (`git add .` then `git commit -m "..."`), then retry. |
| `rejected ... fetch first` / `non-fast-forward` on push | Someone pushed before you. Run `git pull`, fix conflicts if any, then `git push`. |
| `You are in 'detached HEAD' state` | You are not on a branch. Run `git checkout main` or `git checkout your-branch`. |
| `fatal: not a git repository` | You are in the wrong folder. `cd` into the project folder. |
| `Permission denied (publickey)` | SSH key problem. Ask the Tech Lead; or clone with the HTTPS URL instead. |
| Godot shows a scene as changed after you only opened it | Do not commit it unless you meant to change it: `git restore path/to/file.tscn`. |

## Using VSCode instead of the terminal

The *Source Control* icon (left sidebar, third icon) offers the same actions: click `+` to stage, type a message and press **Commit**, then **Sync Changes** (pull + push). The terminal commands above are still worth learning because they work everywhere and are easier to ask for help with.
