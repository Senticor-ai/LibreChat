/**
 * Update German Social Law Agent to fix model and projectIds
 * Run with: node config/update-german-social-law-agent.js
 */

const path = require('path');
const mongoose = require('mongoose');
require('module-alias')({ base: path.resolve(__dirname, '..', 'api') });
require('dotenv').config();

const connect = require('./connect');
const { getAgents } = require('~/models/Agent');

async function updateGermanSocialLawAgent() {
  try {
    console.log('🔧 Updating German Social Law Agent...\n');

    await connect();
    console.log('✅ Connected to database\n');

    // Find the agent by name
    const existingAgents = await getAgents({
      name: 'Sozialrecht-Berater Deutschland'
    });

    if (!existingAgents || existingAgents.length === 0) {
      console.log('❌ Agent "Sozialrecht-Berater Deutschland" not found in database.');
      console.log('   Please run the seed script first: node config/seed-german-social-law-agent.js');
      process.exit(0);
    }

    const agent = existingAgents[0];
    console.log('📋 Current Agent State:');
    console.log('=====================================');
    console.log(`Name: ${agent.name}`);
    console.log(`ID: ${agent.id}`);
    console.log(`Model: ${agent.model}`);
    console.log(`Project IDs: ${JSON.stringify(agent.projectIds)}`);
    console.log('=====================================\n');

    // Update the agent directly in the database
    const Agent = mongoose.connection.collection('agents');

    const updateResult = await Agent.updateOne(
      { _id: agent._id },
      {
        $set: {
          model: 'google/gemini-3-pro-preview',
          projectIds: [],  // Empty array like UI agents
          updatedAt: new Date()
        }
      }
    );

    console.log('🔄 Update Result:');
    console.log(`   Matched: ${updateResult.matchedCount}`);
    console.log(`   Modified: ${updateResult.modifiedCount}`);
    console.log('');

    if (updateResult.modifiedCount > 0) {
      console.log('✅ Agent updated successfully!');
      console.log('');
      console.log('📋 New State:');
      console.log('   Model: google/gemini-3-pro-preview');
      console.log('   Project IDs: []');
      console.log('');
      console.log('🔄 Next steps:');
      console.log('   1. Restart LibreChat: docker-compose restart api');
      console.log('   2. Clear browser cache/localStorage');
      console.log('   3. Refresh the page');
    } else {
      console.log('⚠️  No changes made (agent might already be up to date)');
    }

    process.exit(0);
  } catch (error) {
    console.error('❌ Error updating agent:', error);
    process.exit(1);
  }
}

updateGermanSocialLawAgent();
