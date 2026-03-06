#!/bin/bash

# Store Docker files temporarily
echo "Backing up Docker files..."
cp public/Dockerfile /tmp/
cp public/docker-compose.yml /tmp/
cp public/nginx.conf /tmp/

# Clean public directory but preserve .git
mv public/.git /tmp/.git

# Remove everything in public
rm -rf public/*

# Restore .git
mv /tmp/.git public/

# Build the project
echo "Building Hugo site..."
hugo -t PaperMod

# Restore Docker files
echo "Restoring Docker files..."
cp /tmp/Dockerfile public/
cp /tmp/docker-compose.yml public/
cp /tmp/nginx.conf public/

# Go to public folder
cd public

# Add changes
git add .

# Commit changes with timestamp
msg="Rebuilding site $(date)"
git commit -m "$msg"

# Push to GitHub Pages
git push origin main

# Go back to the main project directory
cd ..

# Commit source files changes
git add .
git commit -m "Update source files"
git push origin main