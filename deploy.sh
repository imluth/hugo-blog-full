#!/bin/bash

# Build the project
hugo -t PaperMod

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