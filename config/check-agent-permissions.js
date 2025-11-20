/**
 * Check agent and its permissions
 * Run with: node config/check-agent-permissions.js
 */

const path = require('path');
const mongoose = require('mongoose');
require('module-alias')({ base: path.resolve(__dirname, '..', 'api') });
require('dotenv').config();

const connect = require('./connect');
const { getAgents } = require('~/models/Agent');
const ACLEntry = require('~/models/schema/aclEntry');
const { ResourceType } = require('librechat-data-provider');

async function checkAgentPermissions() {
  try {
    console.log('🔍 Checking German Social Law Agent and its permissions...\n');

    await connect();
    console.log('✅ Connected to database\n');

    // Find the agent by name
    const existingAgents = await getAgents({
      name: 'Sozialrecht-Berater Deutschland'
    });

    if (!existingAgents || existingAgents.length === 0) {
      console.log('❌ Agent "Sozialrecht-Berater Deutschland" not found in database.');
      process.exit(0);
    }

    const agent = existingAgents[0];
    console.log('📋 AGENT DETAILS');
    console.log('=====================================');
    console.log(`Name: ${agent.name}`);
    console.log(`ID: ${agent.id}`);
    console.log(`_id: ${agent._id}`);
    console.log(`Provider: ${agent.provider}`);
    console.log(`Model: ${agent.model}`);
    console.log(`Category: ${agent.category}`);
    console.log(`Author: ${agent.author}`);
    console.log(`Project IDs: ${JSON.stringify(agent.projectIds)}`);
    console.log(`Tools: ${JSON.stringify(agent.tools)}`);
    console.log(`Created: ${agent.createdAt}`);
    console.log(`Updated: ${agent.updatedAt}`);
    console.log('=====================================\n');

    // Check ACL entries for this agent
    console.log('🔐 PERMISSION ENTRIES (ACL)');
    console.log('=====================================');

    const aclEntries = await ACLEntry.find({
      resourceType: ResourceType.AGENT,
      resourceId: agent._id
    }).lean();

    if (aclEntries.length === 0) {
      console.log('⚠️  NO PERMISSIONS FOUND!');
      console.log('This is likely why the agent is not visible to users.');
    } else {
      console.log(`Found ${aclEntries.length} permission entries:\n`);
      aclEntries.forEach((entry, index) => {
        console.log(`Permission ${index + 1}:`);
        console.log(`  Principal Type: ${entry.principalType}`);
        console.log(`  Principal ID: ${entry.principalId || 'null (public)'}`);
        console.log(`  Resource Type: ${entry.resourceType}`);
        console.log(`  Resource ID: ${entry.resourceId}`);
        console.log(`  Access Role: ${entry.accessRoleId}`);
        console.log(`  Created: ${entry.createdAt}`);
        console.log('');
      });
    }
    console.log('=====================================\n');

    // Recommendations
    console.log('💡 RECOMMENDATIONS');
    console.log('=====================================');

    if (aclEntries.length === 0) {
      console.log('❌ No permissions found - agent is not accessible to anyone!');
      console.log('');
      console.log('To fix this, run:');
      console.log('  1. Delete the agent: node config/delete-german-social-law-agent.js');
      console.log('  2. Recreate it: node config/seed-german-social-law-agent.js');
      console.log('  3. Run migration: npm run migrate:agent-permissions');
    } else {
      const hasPublicPermission = aclEntries.some(e => e.principalType === 'public');
      if (hasPublicPermission) {
        console.log('✅ Public permission exists - agent should be visible to all users');
        console.log('');
        console.log('If still not visible in UI:');
        console.log('  1. Clear browser cache/localStorage');
        console.log('  2. Restart LibreChat container: docker-compose restart api');
        console.log('  3. Check browser console for errors');
      } else {
        console.log('⚠️  No public permission - agent may only be visible to specific users');
        console.log('');
        console.log('To make it public, run:');
        console.log('  npm run migrate:agent-permissions');
      }
    }
    console.log('=====================================\n');

    process.exit(0);
  } catch (error) {
    console.error('❌ Error checking agent:', error);
    process.exit(1);
  }
}

// Run the check function
checkAgentPermissions();
