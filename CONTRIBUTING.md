# Contributing to Ledgile

First off, thank you for considering contributing to Ledgile! It's people like you that make Ledgile such a great tool for shopkeepers.

## Where do I go from here?

If you've noticed a bug or have a feature request, make sure to check our [Issues](../../issues) to see if someone else in the community has already created a ticket. If not, go ahead and [make one](../../issues/new)!

## Fork & create a branch

If this is something you think you can fix, then fork Ledgile and create a branch with a descriptive name.

A good branch name would be (where issue #325 is the ticket you're working on):

```sh
git checkout -b 325-add-dark-mode-support
```

## Implementation Guidelines

1. **Architecture**: Ensure any UI additions follow the existing architecture (MVC with programmatic UI or XIBs where appropriate).
2. **Machine Learning**: If updating ML models, ensure the new models are compiled (`.mlmodelc`) and tracked using Git LFS. Keep the model size under 50MB if possible for on-device performance.
3. **Database Operations**: Ensure all SQLite transactions are executed asynchronously so as not to block the main UI thread. 

## Get the style right

Your patch should format code in the same style that is already used in Ledgile. We generally follow the standard Swift API Design Guidelines.

## Make a Pull Request

At this point, you should switch back to your master branch and make sure it's up to date with Ledgile's master branch:

```sh
git remote add upstream git@github.com:Souravgupta2111/Ledgile.git
git fetch upstream
git pull upstream main
```

Then update your feature branch from your local copy of master, and push it!

```sh
git checkout 325-add-dark-mode-support
git rebase main
git push --set-upstream origin 325-add-dark-mode-support
```

Finally, go to GitHub and [make a Pull Request](../../compare) :D
