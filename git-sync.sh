#!/bin/bash
# Simple script to sync changes to git automatically

# Ensure we are in the project root
cd "$(dirname "$0")"

echo "Syncing changes to git..."

# Add all changes
git add .

# Commit with a timestamp (only if there are changes)
if ! git diff-index --quiet HEAD --; then
    COMMIT_MSG="Auto-sync update: $(date +'%Y-%m-%d %H:%M:%S')"
    git commit -m "$COMMIT_MSG"
    echo "Committed changes: $COMMIT_MSG"
else
    echo "No local changes to commit."
fi

# Pull any remote changes (rebase to avoid merge commits)
echo "Pulling latest changes from remote..."
git pull --rebase origin main

# Push to origin
echo "Pushing to remote origin..."
git push origin main

echo "Sync complete!"
