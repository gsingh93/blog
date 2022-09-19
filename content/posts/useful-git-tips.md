---
layout: post
title: "Useful Git Tips"
date: 2014-04-27 17:46:22 -0400
comments: true
published: true
tags: ['git']
---

I've noticed that when it comes to Git tutorials, there's only the "Intro to Git" or the "Here's how you do X with Git", but there aren't any tutorials that take you from a Git beginner to a Git master. This post is supposed to be a starting point for that. It will provide some useful tips and concepts that I use everyday, which allows me to use Git to the fullest extent. For anyone who's interested in learning more, definitely check out the [Pro Git](http://git-scm.com/book) that's freely available online. I've read that book from beginning to end and I've found it very interesting and educational.

Note that this tutorial requires basic knowledge of Git. That is, you should know what Git is, how to add, commit, and push changes, and the very basics of branches and merging.

<!-- more -->

## Git Number

The first tip I'd recommend is to get [Git Number](https://github.com/holygeek/git-number). Git Number saves a ton of time when doing anything with Git. Instead of typing `git status`, try typing `git number`. You'll see the same output you'd normally see but with numbers in front. Now to perform any operation on a file, you just need to use it's corresponding number. So instead of typing `git add the/path/to/this/file/is/so/long.txt`, you'll just be able to type `git number add 1`. Note that this works on any git command that requires a file name, so it'll work with commands like `git rm` and `git checkout` too. Where git number really shines is it's ability to do operations on ranges. For example, you could run the command `git number add 1-3,5,8` to add the files 1, 2, 3, 5, and 8, but leave all other files unmodified.

If you've read my [useful Bash aliases](/posts/useful-bash-aliases) post, you'll see I have two aliases for `git number` that you might find useful:

``` bash
alias gn='git number'
alias ga='git number add'
```

## .gitconfig and Aliases

Git allows you to have aliases apart from Bash aliases. These aliases can be added in your `.gitconfig` file which should be located in your home directory (go ahead and make one if it's not there for some reason). You can also set colors in your `.gitconfig` which makes the output of `git status` or `git diff` more readable. Here's my full `.gitconfig` file:

``` ini .gitconfig
[user]
	name = Gulshan Singh
	email = gulshan@umich.edu
[color]
	diff = auto
	status = auto
	branch = auto
	interactive = auto
	ui = true
	pager = true
[color "status"]
	added = yellow
	changed = green
	untracked = red
[core]
	pager = less -FRSX
	whitespace=fix,-indent-with-non-tab,trailing-space,cr-at-eol
	editor = /usr/bin/emacs
[alias]
	st = status
	ci = commit
	co = checkout
	w = whatchanged
	amend = commit --amend --no-edit
[push]
	default = upstream
```

Sidenote: One useful alias that I'd also like to mention needs to be set in the Bash shell, not in the .gitconfig:

``` bash
alias git-root='cd "`git rev-parse --show-toplevel`"'
```

Running `git-root` will return you to the top level directory of the Git project.

Anyways, the config is for the most part self explanatory. The `git whatchanged` command lists changed files, and `git commit amend` is used for modifying a commit. In this particular case, the alias has the `--no-edit` flag, so Git won't bug me about changing the commit message if I'm only modifying or adding files to the previous commit.

You might be interested in looking up the options for the `push.default` setting. Giving this setting a value of `upstream` will push all branches that exist both on your local git repo and on the remote git repo (these branches are known as "tracked" branches). This means that you can type `git push` instead of `git push origin master`.

If you have any other suggestions for useful configuration options, let me know in the comments.

## git log

I hope that you have encountered `git log` by now, because it's a necessary command to use Git effectively. `git log` shows you the history of commits in a repo. Each commit has a SHA1 hash that you can use in other commands that we'll cover later. If you use `git whatchanged` you'll also see every file that was modified in the commit. Here are some useful things you can do with `git log`:

* `git log -p` - This is a very useful command that displays a diff for each file that was modified in the log output.
* `git log <branch-name>` - You can see the log for any branch regardless of the branch you're currently on.
* `git log <filename>` - This shows you all of the commits where `filename` was modified. This is especially useful with the `-p` flag mentioned above.
* `git log --oneline` - This displays each commit as one line and only shows the first seven characters of the hash and the commit message. This is useful for seeing a lot of commits at once without scrolling. I'll be aliasing this command in the future.

These are my most common uses of `git log`, but I recommend you take a look at the Git documentation as there are many more useful options.

## Gitk

Gitk is a useful tool for visualizing your branches and commit history. Simply run `gitk` in the repository and a GUI should popup. Using the GUI is fairly self explanatory. You'll find `gitk` incredibly useful when solving complex branching issues or searching through commits. These things can be done on the command line, but I find `gitk` a lot easier for these tasks.

## git stash

I'm not sure how well known `git stash` is among beginners, so I'll mention it here just in case. If you ever need to switch branches or pull to the current branch without commiting or deleting the changes you've made, you can use `git stash` to store them temporarily. You can then run `git stash pop` to restore those changes. `git stash` will store your changes in a stack, so you can run the command for multiple changes, but `git stash pop` will only pop the latest change on the stack. However, you can still restore changes that aren't at the top of the stack. `git stash list` will display all of your stashes preceded by something like this `stash@{0}`, and you can restore a stash by typing `git stash pop stash@{0}`, changing the 0 to the correct number for the stash you want.

If you forget what contents are in a stash you can run `git show stash@{0}` to see the changes (note that `git show` works on a lot of things other stashes; commits, branches, remotes, tags, etc.). Better yet, just write a descriptive message for the stash when you save it by using `git stash save <message>`.

## Fetching, merging, and rebasing

This section is very important, but if I took the time to write it, this article would be incredibly long. Fortunately, other people have already written this information for me, so I will point you to it.

* [Fetching vs. pulling](http://longair.net/blog/2009/04/16/git-fetch-and-merge/) - This article should also explain a lot about branching, remotes, and merging, but the main take away is how to use fetch and merge without pull. I still use `git pull` most of the time, but knowing how to fetch and merge and how remote branches work is very useful.
* [Fast-forward vs non-fast-forward merging](http://ariya.ofilabs.com/2013/09/fast-forward-git-merge.html)
* [How to rebase](http://git-scm.com/book/en/Git-Branching-Rebasing)

## git checkout and git reset

You've probably used `git checkout` to switch between or create new branches, but you can also use it to checkout older versions of files. Let's say you want to revert changes to a single file. You can run `git checkout <filename>` to revert the file back to it's state on HEAD, or you can do `git checkout <filename> <hash>` to checkout the version from a specific commit. It's also common to use the HEAD~ syntax here as well. So for example, to checkout the version of a file from the previous commit, you can run `git checkout <filename> HEAD~1`, for the second to last commit you can use `HEAD~2`, and so on. You can also checkout specific files from different branches using `git checkout <filename> <branchname>`.

`git reset` is for resetting all files to a certain point. You can use `git reset HEAD~1` to undo the last commit, but keep the commit changes. This is useful when you've committed something you didn't want to commit. To revert the changes as well, you can use `git reset --hard HEAD~1`. Note that you can replace `HEAD~1` with any previous commit or any commit's hash. You can get this hash by using `git log`, and you only need to use enough of the hash so that the commit can be uniquely identified, so you don't have to copy the entire hash.

If you want to revert all of the modifications you've made and not revert the previous commit (this is called reverting to HEAD), you can run `git reset --hard HEAD`, which is the equivalent of calling `git checkout` on all of the modified files. Note that this is a dangerous command and you should only use this when you're sure you need to get rid of all of your changes. Reseting to HEAD by accident is one of the few things you can't fix with `git reflog`, which I'll be talking about next.

## git reflog

All of the knowledge you've gained so far about Git is great, but it also means you have more ways to screw things up. Luckily, when you do you can always turn to `git reflog`. `git reflog` displays a log of not the commit history, but essentially the Git command history. If you ever make a mistake, you can always run `git checkout HEAD@{0}` or `git reset --hard HEAD@{0}` to go to a previous state of the repo, of course replacing the 0 with the corresponding reflog number. This can be used to reset rebases, merges, and everything else Git can do.

## git cherry-pick

This might be a less commonly used feature for you, but it's still good to know. The idea here is that there may be a commit on some branch that you want on another branch. This could be used, for example, to add a security patch to different releases of a product. Let's say there's a commit on the `dev` branch of the repo and you want that on master. First checkout the master branch, and then run `git log dev` and find the SHA1 hash of the commit you want. Copy the hash and use it in this command:

``` bash
git cherry-pick <hash>
```

The commit will then be on the master branch.

## Workflow

I've covered a lot of material on Git features, but I'd like to mention how I like to use these features to effectively work with other collaboratively on projects.

No one on your team should ever commit directly to master. Each team member should have their own dev branch. For example, I always work on `gulshan-dev`. Whether this branch is tracked by the remote repo or not is up to you, but I prefer that my dev branch is tracked so my changes are backed up. Small commits and bug fixes can be committed directly to your dev branch. For larger changes, like adding major features, create a branch from your dev branch to work on that feature (this is called a feature or topic branch).

When the feature is finished, merge it with your dev branch using a non-fast-forward merge. This will allow you to work on smaller things while working on major features, but keep the history separate. Even if you make no changes to your dev branch in the mean time and you can do a fast-forward merge, I'd still recommend to do a non-fast-forward merge so anyone can clearly see the feature branch using something like `gitk`. Once you're ready to put changes on `master`, rebase your dev branch on `master`. After fixing up any conflicts, checkout `master` and merge your dev branch with it. Because you rebased, the merge should be a fast-forward merge by default. Aftert that, you're ready to push to the remote repo.

This workflow should both keep your commit history clean, reduce merge conflict issues, and reduce bugs that are due to Git.

## Conclusion

I've covered a lot of the things that I use regularly that I've noticed a lot of people who use Git don't understand. If you're looking for more stuff to learn, I'd definitely recommend the [Pro Git](http://git-scm.com/book), and I'd encourage you to look up things like remotes, interactive merges and additions, local and remote branch management, tagging, and in general, how Git works. All of those topics are covered in the book. If there's anything you think should be added to the list, let me know in the comments.
