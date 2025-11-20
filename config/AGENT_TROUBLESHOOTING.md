# Agent Creation Troubleshooting - Resolution Documentation

## Problem
The seeded German Social Law Agent was not appearing in the LibreChat UI, even though it existed in the database with proper permissions.

## Investigation Process

### 1. Initial Checks
- ✅ Agent existed in database
- ✅ Agent had correct model (`google/gemini-3-pro-preview`)
- ✅ Agent had public permissions
- ✅ OpenRouter endpoint was configured correctly in `librechat.yaml`

### 2. Comparison with Working Agent
Created scripts to compare the seeded agent with a working UI-created agent:
- `config/compare-agents.js`
- `config/list-all-agents.js`

**Key Findings:**
```
Working UI Agent:
- Author: 691dfbecf4b22cd24137049e (USER ID ✓)
- Project IDs: []
- Permissions: 2 (user + public)

Broken Seeded Agent (Initial):
- Author: 691dfbbf788b4ba186d58d4f (PROJECT ID ✗)
- Project IDs: ["691dfbbf788b4ba186d58d4f"]
- Permissions: 1 (public only)
```

### 3. Root Cause Identified
The original seed script (`config/seed-german-social-law-agent.js`) had a **critical bug on line 126**:

```javascript
// WRONG - Sets author to a PROJECT ID
author: globalProject._id,
```

The `author` field **must be a User ID**, not a Project ID. This caused the agent to be filtered out by the frontend.

### 4. Solution Reference
Found a working agent creation script in the broken LibreChat instance:
- `/Users/wolfgang/workspace/LibreChat-broken/config/create-ki-referent-agent.js`

This script correctly:
1. Gets an admin user from the database
2. Uses the admin user's `_id` as the author
3. Uses the "instance" project instead of GLOBAL_PROJECT_NAME
4. Grants public permissions for visibility

## The Fix

### Updated `config/seed-german-social-law-agent.js`

**Before (BROKEN):**
```javascript
const { Constants, PrincipalType, ResourceType, AccessRoleIds } = require('librechat-data-provider');

// Get the global project
const globalProject = await getProjectByName(Constants.GLOBAL_PROJECT_NAME);

// Create the agent with project as author (WRONG!)
const createdAgent = await createAgent({
  ...germanSocialLawAgent,
  id: `agent_${nanoid()}`,
  author: globalProject._id, // PROJECT ID - CAUSES AGENT TO BE INVISIBLE!
  projectIds: [globalProject._id],
});
```

**After (FIXED):**
```javascript
const { SystemRoles, PrincipalType, ResourceType, AccessRoleIds } = require('librechat-data-provider');

// Get the first admin user to be the agent author
const { User } = require('~/db/models');
const adminUser = await User.findOne({ role: SystemRoles.ADMIN });

if (!adminUser) {
  throw new Error('No admin user found. Please create an admin user first.');
}

console.log(`✅ Using admin user ${adminUser.email} as agent author`);

// Get the global "instance" project
const { Project } = require('~/db/models');
const globalProject = await Project.findOne({ name: 'instance' });

if (!globalProject) {
  throw new Error('Global "instance" project not found');
}

console.log(`✅ Using global project: ${globalProject.name} (${globalProject._id})`);

// Create the agent with admin user as author (CORRECT!)
const createdAgent = await createAgent({
  ...germanSocialLawAgent,
  id: `agent_${nanoid()}`,
  author: adminUser._id, // USER ID - CORRECT!
  projectIds: [globalProject._id],
});
```

## Steps to Recreate Agent (After Fix)

1. **Delete existing broken agent:**
   ```bash
   docker exec -it LibreChat node config/delete-german-social-law-agent.js
   ```

2. **Copy updated script to container:**
   ```bash
   docker cp config/seed-german-social-law-agent.js LibreChat:/app/config/seed-german-social-law-agent.js
   ```

3. **Create new agent with fixed script:**
   ```bash
   docker exec -it LibreChat node config/seed-german-social-law-agent.js
   ```

4. **Run agent permissions migration:**
   ```bash
   docker exec -it LibreChat npm run migrate:agent-permissions
   ```
   Or if in container:
   ```bash
   docker exec -it LibreChat node config/migrate-agent-permissions.js
   ```

5. **Restart container:**
   ```bash
   docker-compose restart api
   ```

6. **Clear browser cache and refresh the page**

## Why This Fix Works

### The Author Field Requirement
LibreChat's agent system requires:
- The `author` field must reference a **User document** (`User._id`)
- NOT a Project, Group, or any other document type
- The frontend filters out agents with invalid author references

### The "instance" Project
- The working pattern uses `Project.findOne({ name: 'instance' })`
- Instead of `getProjectByName(Constants.GLOBAL_PROJECT_NAME)`
- This ensures compatibility with LibreChat's project structure

### Permission Migration
After creating an agent programmatically:
- The agent needs migration to set up proper ACL entries
- Migration grants owner permissions to the author
- Without migration, the agent may not appear to all users

## Key Lessons

1. ✅ **Author field MUST be a User ID**, never a Project ID
2. ✅ Use the "instance" project for global agents
3. ✅ Run `migrate:agent-permissions` after creating agents programmatically
4. ✅ Always reference working examples when creating system agents
5. ✅ Use comparison scripts to debug agent visibility issues

## Debugging Scripts Created

### `config/compare-agents.js`
Compares two agents side-by-side to identify differences:
- Author fields
- Project IDs
- Permissions
- Model names

Usage:
```bash
docker exec -it LibreChat node config/compare-agents.js
```

### `config/list-all-agents.js`
Lists all agents in the database with their permissions:

Usage:
```bash
docker exec -it LibreChat node config/list-all-agents.js
```

### `config/check-agent.js`
Checks details for the German Social Law Agent:

Usage:
```bash
docker exec -it LibreChat node config/check-agent.js
```

## Related Files

**Fixed Script:**
- `config/seed-german-social-law-agent.js` - Main creation script (FIXED)

**Deletion Script:**
- `config/delete-german-social-law-agent.js` - Removes the agent

**Debugging Scripts:**
- `config/check-agent.js` - Check single agent details
- `config/compare-agents.js` - Compare two agents
- `config/list-all-agents.js` - List all agents with permissions

**Working Reference (External):**
- `/Users/wolfgang/workspace/LibreChat-broken/config/create-ki-referent-agent.js`

## OpenRouter Configuration

Updated `librechat.yaml` to only offer two models:

```yaml
endpoints:
  custom:
    - name: 'OpenRouter'
      apiKey: '${OPENROUTER_KEY}'
      baseURL: 'https://openrouter.ai/api/v1'
      models:
        default:
          - 'tngtech/deepseek-r1t2-chimera'
          - 'google/gemini-3-pro-preview'
        fetch: false
      titleConvo: true
      titleModel: 'google/gemini-3-pro-preview'
      summarize: false
      summaryModel: 'google/gemini-3-pro-preview'
```

The agent uses `google/gemini-3-pro-preview` model.

## Backend Code Analysis

The agent filtering happens at multiple layers:

1. **Database Query** (`api/models/Agent.js:551`):
   - `getListAgentsByAccess` filters by ACL accessible IDs
   - Doesn't filter by model availability

2. **API Controller** (`api/server/controllers/agents/v1.js:491`):
   - `getListAgentsHandler` fetches accessible agent IDs via ACL
   - Returns agents based on permissions only

3. **Frontend** (inferred):
   - May filter agents with invalid author references
   - This is why setting author to a Project ID broke visibility

## Success Criteria

✅ Agent appears in LibreChat UI under "My Agents"
✅ Agent is publicly accessible to all users
✅ Agent uses the correct model (`google/gemini-3-pro-preview`)
✅ Agent has proper permissions (owner + public)
✅ Agent author is a valid user ID (not a project ID)

## Common Pitfalls to Avoid

❌ Setting `author` to a Project ID
❌ Using `Constants.GLOBAL_PROJECT_NAME` instead of "instance"
❌ Forgetting to run permission migration
❌ Not clearing browser cache after changes
❌ Using a model that isn't in the endpoint configuration

---

**Date Resolved:** 2025-11-19
**LibreChat Version:** v0.8.1-rc1
**Resolved By:** Claude Code (Anthropic)
