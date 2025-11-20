/**
 * Check script for German Social Law Agent
 * Run with: node config/check-agent.js
 */

const path = require('path');
require('module-alias')({ base: path.resolve(__dirname, '..', 'api') });
require('dotenv').config();

const connect = require('./connect');
const { getAgents } = require('~/models/Agent');

async function checkAgent() {
  try {
    console.log('🔍 Checking German Social Law Agent...');

    await connect();
    console.log('✅ Connected to database');

    // Find the agent by name
    const existingAgents = await getAgents({
      name: 'Sozialrecht-Berater Deutschland'
    });

    if (!existingAgents || existingAgents.length === 0) {
      console.log('❌ Agent "Sozialrecht-Berater Deutschland" not found in database.');
      process.exit(0);
    }

    const agent = existingAgents[0];
    console.log('\n📋 Agent Details:');
    console.log('=====================================');
    console.log(`Name: ${agent.name}`);
    console.log(`ID: ${agent.id}`);
    console.log(`Provider: ${agent.provider}`);
    console.log(`Model: ${agent.model}`);
    console.log(`Category: ${agent.category}`);
    console.log(`Author: ${agent.author}`);
    console.log(`Access Level: ${agent.access_level}`);
    console.log(`Project IDs: ${JSON.stringify(agent.projectIds)}`);
    console.log(`Tools: ${JSON.stringify(agent.tools)}`);
    console.log(`Created: ${agent.createdAt}`);
    console.log(`Updated: ${agent.updatedAt}`);
    console.log('=====================================\n');

    // Check full agent object
    console.log('Full agent object:');
    console.log(JSON.stringify(agent, null, 2));

    process.exit(0);
  } catch (error) {
    console.error('❌ Error checking agent:', error);
    process.exit(1);
  }
}

// Run the check function
checkAgent();
