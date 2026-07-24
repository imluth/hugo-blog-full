#!/bin/bash
set -e

DOCKER_FILES=("Dockerfile" "docker-compose.yml" "nginx.conf")

# Ensure public/ is the hugo-blog repo
if [ ! -d "public/.git" ]; then
    echo "ERROR: public/.git not found. Re-cloning hugo-blog repo..."
    rm -rf public
    git clone git@github.com:imluth/hugo-blog.git public
fi

# Back up Docker files from public/
echo "Backing up Docker files..."
for f in "${DOCKER_FILES[@]}"; do
    if [ -f "public/$f" ]; then
        cp "public/$f" "/tmp/$f"
    else
        echo "WARNING: public/$f not found, skipping backup"
    fi
done

# Clean public/ preserving .git and .gitignore
echo "Cleaning public/..."
find public -maxdepth 1 ! -name '.git' ! -name '.gitignore' ! -name '.' ! -name 'public' -exec rm -rf {} +

# Build Hugo site
echo "Building Hugo site..."
hugo -t PaperMod

# Restore Docker files
echo "Restoring Docker files..."
for f in "${DOCKER_FILES[@]}"; do
    if [ -f "/tmp/$f" ]; then
        cp "/tmp/$f" "public/$f"
    else
        echo "WARNING: /tmp/$f not found, skipping restore"
    fi
done

# Commit and push public/ to hugo-blog repo
echo "Pushing to hugo-blog..."
find public -name '.DS_Store' -delete
cd public
git add .
msg="Rebuilding site $(date)"
git commit -m "$msg" || echo "No changes to commit in public/"
git push origin main
cd ..

# Commit and push source repo
echo "Pushing source repo..."
git add .
git commit -m "Update source files" || echo "No changes to commit in source repo"
git push origin main

echo "Deploy complete!"
