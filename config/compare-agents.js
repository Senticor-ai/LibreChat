/**
 * Compare UI-created agent with seeded agent
 * Run with: node config/compare-agents.js
 */

const path = require('path');
const mongoose = require('mongoose');
require('module-alias')({ base: path.resolve(__dirname, '..', 'api') });
require('dotenv').config();

const connect = require('./connect');
const { getAgents } = require('~/models/Agent');
const { ResourceType } = require('librechat-data-provider');

async function compareAgents() {
  try {
    console.log('🔍 Comparing agents...\n');

    await connect();
    console.log('✅ Connected to database\n');

    // Get the UI-created agent (working one)
    const uiAgent = await getAgents({ id: 'agent_shJyIEHR7SSPc0TSOQOBD' });

    // Get the seeded agent
    const seededAgents = await getAgents({ name: 'Sozialrecht-Berater Deutschland' });

    if (!uiAgent || uiAgent.length === 0) {
      console.log('❌ UI agent not found');
      process.exit(1);
    }

    console.log('✅ UI AGENT (WORKING)');
    console.log('=====================================');
    const ui = uiAgent[0];
    console.log(`Name: ${ui.name}`);
    console.log(`ID: ${ui.id}`);
    console.log(`_id: ${ui._id}`);
    console.log(`Provider: ${ui.provider}`);
    console.log(`Model: ${ui.model}`);
    console.log(`Author: ${ui.author}`);
    console.log(`Project IDs: ${JSON.stringify(ui.projectIds)}`);
    console.log('=====================================\n');

    // Check permissions for UI agent
    const ACLEntries = mongoose.connection.collection('aclentries');
    const uiPermissions = await ACLEntries.find({
      resourceType: ResourceType.AGENT,
      resourceId: ui._id
    }).toArray();
    console.log(`🔐 UI Agent Permissions: ${uiPermissions.length} entries`);
    uiPermissions.forEach((p, i) => {
      console.log(`  ${i + 1}. ${p.principalType} - ${p.accessRoleId} ${p.principalId ? `(${p.principalId})` : '(public)'}`);
    });
    console.log('\n');

    if (!seededAgents || seededAgents.length === 0) {
      console.log('❌ SEEDED AGENT NOT FOUND');
      console.log('   The agent may not have been created successfully.');
      console.log('   Try running: node config/seed-german-social-law-agent.js');
      process.exit(0);
    }

    console.log('⚠️  SEEDED AGENT (NOT WORKING)');
    console.log('=====================================');
    const seeded = seededAgents[0];
    console.log(`Name: ${seeded.name}`);
    console.log(`ID: ${seeded.id}`);
    console.log(`_id: ${seeded._id}`);
    console.log(`Provider: ${seeded.provider}`);
    console.log(`Model: ${seeded.model}`);
    console.log(`Author: ${seeded.author}`);
    console.log(`Project IDs: ${JSON.stringify(seeded.projectIds)}`);
    console.log('=====================================\n');

    // Check permissions for seeded agent
    const seededPermissions = await ACLEntries.find({
      resourceType: ResourceType.AGENT,
      resourceId: seeded._id
    }).toArray();
    console.log(`🔐 Seeded Agent Permissions: ${seededPermissions.length} entries`);
    seededPermissions.forEach((p, i) => {
      console.log(`  ${i + 1}. ${p.principalType} - ${p.accessRoleId} ${p.principalId ? `(${p.principalId})` : '(public)'}`);
    });
    console.log('\n');

    // Compare
    console.log('🔎 DIFFERENCES');
    console.log('=====================================');

    const diffs = [];
    if (ui.author?.toString() !== seeded.author?.toString()) {
      diffs.push(`Author: UI=${ui.author} vs Seeded=${seeded.author}`);
    }
    if (JSON.stringify(ui.projectIds) !== JSON.stringify(seeded.projectIds)) {
      diffs.push(`ProjectIds: UI=${JSON.stringify(ui.projectIds)} vs Seeded=${JSON.stringify(seeded.projectIds)}`);
    }
    if (ui.model !== seeded.model) {
      diffs.push(`Model: UI=${ui.model} vs Seeded=${seeded.model}`);
    }
    if (uiPermissions.length !== seededPermissions.length) {
      diffs.push(`Permissions count: UI=${uiPermissions.length} vs Seeded=${seededPermissions.length}`);
    }

    if (diffs.length === 0) {
      console.log('No major differences found in basic fields');
    } else {
      diffs.forEach(d => console.log(`⚠️  ${d}`));
    }
    console.log('=====================================\n');

    // Recommendations
    if (seededPermissions.length === 0) {
      console.log('💡 ISSUE FOUND: Seeded agent has NO permissions!');
      console.log('');
      console.log('Fix:');
      console.log('  1. Delete: node config/delete-german-social-law-agent.js');
      console.log('  2. Recreate: node config/seed-german-social-law-agent.js');
      console.log('  3. Migrate: npm run migrate:agent-permissions');
    }

    process.exit(0);
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

compareAgents();
