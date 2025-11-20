/**
 * List all agents in the database and show their full details
 * Run with: node config/list-all-agents.js
 */

const path = require('path');
const mongoose = require('mongoose');
require('module-alias')({ base: path.resolve(__dirname, '..', 'api') });
require('dotenv').config();

const connect = require('./connect');

async function listAllAgents() {
  try {
    console.log('📋 Listing all agents in database...\n');

    await connect();
    console.log('✅ Connected to database\n');

    // Get all agents directly from the collection
    const Agent = mongoose.connection.collection('agents');
    const allAgents = await Agent.find({}).toArray();

    console.log(`Found ${allAgents.length} total agents:\n`);
    console.log('=====================================\n');

    allAgents.forEach((agent, index) => {
      console.log(`Agent ${index + 1}:`);
      console.log(`  Name: ${agent.name}`);
      console.log(`  ID: ${agent.id}`);
      console.log(`  _id: ${agent._id}`);
      console.log(`  Provider: ${agent.provider}`);
      console.log(`  Model: ${agent.model}`);
      console.log(`  Author: ${agent.author}`);
      console.log(`  Project IDs: ${JSON.stringify(agent.projectIds)}`);
      console.log(`  Category: ${agent.category || 'none'}`);
      console.log(`  Created: ${agent.createdAt}`);
      console.log(`  Updated: ${agent.updatedAt}`);
      console.log('');
    });

    console.log('=====================================\n');

    // Now check permissions for all agents
    const ACLEntries = mongoose.connection.collection('aclentries');
    const { ResourceType } = require('librechat-data-provider');

    for (const agent of allAgents) {
      const permissions = await ACLEntries.find({
        resourceType: ResourceType.AGENT,
        resourceId: agent._id
      }).toArray();

      console.log(`🔐 Permissions for "${agent.name}":`);
      if (permissions.length === 0) {
        console.log('   ⚠️  NO PERMISSIONS');
      } else {
        permissions.forEach((p, i) => {
          console.log(`   ${i + 1}. ${p.principalType} - ${p.accessRoleId || 'no role'} ${p.principalId ? `(${p.principalId})` : '(public)'}`);
        });
      }
      console.log('');
    }

    process.exit(0);
  } catch (error) {
    console.error('❌ Error:', error);
    process.exit(1);
  }
}

listAllAgents();
