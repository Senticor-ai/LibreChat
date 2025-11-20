/**
 * Fix German Social Law Agent permissions by adding owner permission
 * Run with: node config/fix-agent-permissions.js
 */

const path = require('path');
const mongoose = require('mongoose');
require('module-alias')({ base: path.resolve(__dirname, '..', 'api') });
require('dotenv').config();

const connect = require('./connect');
const { getAgents } = require('~/models/Agent');
const { grantPermission } = require('~/server/services/PermissionService');
const { AccessRoleIds, ResourceType, PrincipalType } = require('librechat-data-provider');

async function fixAgentPermissions() {
  try {
    console.log('🔧 Fixing German Social Law Agent permissions...\n');

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
    console.log('📋 Agent Details:');
    console.log('=====================================');
    console.log(`Name: ${agent.name}`);
    console.log(`ID: ${agent.id}`);
    console.log(`_id: ${agent._id}`);
    console.log(`Author: ${agent.author}`);
    console.log('=====================================\n');

    // Check existing permissions
    const ACLEntries = mongoose.connection.collection('aclentries');
    const existingPermissions = await ACLEntries.find({
      resourceType: ResourceType.AGENT,
      resourceId: agent._id
    }).toArray();

    console.log(`🔐 Current Permissions: ${existingPermissions.length} entries`);
    existingPermissions.forEach((p, i) => {
      console.log(`  ${i + 1}. ${p.principalType} - ${p.accessRoleId || 'no role'} ${p.principalId ? `(${p.principalId})` : '(public)'}`);
    });
    console.log('');

    // Check if owner permission already exists
    const hasOwnerPermission = existingPermissions.some(
      p => p.principalType === PrincipalType.USER && p.principalId?.toString() === agent.author?.toString()
    );

    if (hasOwnerPermission) {
      console.log('✅ Owner permission already exists. No action needed.');
      process.exit(0);
    }

    // Grant owner permission to the author
    console.log('➕ Adding owner permission for author...');
    await grantPermission({
      principalType: PrincipalType.USER,
      principalId: agent.author,
      resourceType: ResourceType.AGENT,
      resourceId: agent._id,
      accessRoleId: AccessRoleIds.AGENT_OWNER,
    });

    console.log('✅ Owner permission granted!\n');

    // Verify the permission was added
    const updatedPermissions = await ACLEntries.find({
      resourceType: ResourceType.AGENT,
      resourceId: agent._id
    }).toArray();

    console.log(`🔐 Updated Permissions: ${updatedPermissions.length} entries`);
    updatedPermissions.forEach((p, i) => {
      console.log(`  ${i + 1}. ${p.principalType} - ${p.accessRoleId || 'no role'} ${p.principalId ? `(${p.principalId})` : '(public)'}`);
    });
    console.log('');

    console.log('🎉 Permissions fixed successfully!');
    console.log('');
    console.log('🔄 Next steps:');
    console.log('   1. Restart LibreChat: docker-compose restart api');
    console.log('   2. Clear browser cache/localStorage');
    console.log('   3. Refresh the page');

    process.exit(0);
  } catch (error) {
    console.error('❌ Error fixing permissions:', error);
    process.exit(1);
  }
}

fixAgentPermissions();
