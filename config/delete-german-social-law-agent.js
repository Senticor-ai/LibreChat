/**
 * Delete script for German Social Law Agent
 * Run with: node config/delete-german-social-law-agent.js
 */

const path = require('path');
require('module-alias')({ base: path.resolve(__dirname, '..', 'api') });
require('dotenv').config();

const connect = require('./connect');
const { getAgents, deleteAgent } = require('~/models/Agent');

async function deleteGermanSocialLawAgent() {
  try {
    console.log('🗑️  Starting German Social Law Agent deletion...');

    await connect();
    console.log('✅ Connected to database');

    // Find the agent by name
    const existingAgents = await getAgents({
      name: 'Sozialrecht-Berater Deutschland'
    });

    if (!existingAgents || existingAgents.length === 0) {
      console.log('⚠️  Agent "Sozialrecht-Berater Deutschland" not found. Nothing to delete.');
      process.exit(0);
    }

    const agent = existingAgents[0];
    console.log(`📋 Found agent: ${agent.name} (ID: ${agent.id})`);

    // Delete the agent
    await deleteAgent({ id: agent.id });

    console.log('✅ Successfully deleted German Social Law Agent');
    console.log('   You can now run the seed script to create a new version with updated configuration.');

    process.exit(0);
  } catch (error) {
    console.error('❌ Error deleting German Social Law Agent:', error);
    process.exit(1);
  }
}

// Run the deletion function
deleteGermanSocialLawAgent();
