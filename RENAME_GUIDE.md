# How to Rename Your GitHub Repository

## Current Repository Name
`water-level-sensor-probe-with-esphome-` (note the trailing hyphen)

## Suggested New Names
Here are some better naming options:
- `water-level-sensor-esphome` (recommended - shorter and cleaner)
- `esphome-water-level-sensor`
- `heatpump-water-level-monitor`
- `water-level-sensor-probe-esphome` (removes trailing hyphen)

## Steps to Rename on GitHub

### 1. Navigate to Repository Settings
1. Go to your repository on GitHub: https://github.com/MomoRC-tech/water-level-sensor-probe-with-esphome-
2. Click on the **Settings** tab (you need admin/owner permissions)

### 2. Rename the Repository
1. Scroll down to the **Repository name** section at the top
2. Enter your new repository name in the text field
3. Click **Rename** button
4. GitHub will show you a warning about the impact - read it carefully

### 3. Important Notes After Renaming

#### Automatic Redirects
- GitHub automatically sets up redirects from the old URL to the new URL
- Existing clones, forks, and links will continue to work temporarily
- However, it's best practice to update all references

#### Update Your Local Clone
After renaming on GitHub, update your local repository:

```bash
# Check current remote URL
git remote -v

# Update the remote URL (replace NEW-NAME with your chosen name)
git remote set-url origin https://github.com/MomoRC-tech/NEW-NAME.git

# Verify the change
git remote -v
```

#### Update Any Documentation
- Update any documentation that references the old repository name
- Update links in README files, wikis, or other projects
- Update any CI/CD configurations that use the repository URL

#### Notify Collaborators
- Let any collaborators know about the rename
- They will need to update their local clones using the command above

### 4. What GitHub Does Automatically
- Redirects web traffic from old URL to new URL
- Updates all issues, pull requests, and wikis
- Preserves all stars, watchers, and forks
- Maintains commit history

### 5. What You Need to Update Manually
- Local clones (see commands above)
- Any hardcoded repository URLs in scripts or configurations
- Documentation or external links outside of GitHub
- CI/CD pipeline configurations
- Package registry references
- Webhooks and integrations

## Alternative: Keep Current Name
If you prefer to keep the current name structure, that's perfectly fine! The trailing hyphen is unusual but not problematic for functionality.
