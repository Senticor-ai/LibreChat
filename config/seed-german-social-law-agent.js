/**
 * Seed script to create German Social Law Agent
 * Run with: node config/seed-german-social-law-agent.js
 */

const path = require('path');
const mongoose = require('mongoose');
const { nanoid } = require('nanoid');
require('module-alias')({ base: path.resolve(__dirname, '..', 'api') });
require('dotenv').config();

const connect = require('./connect');
const { createAgent, getAgents } = require('~/models/Agent');
const { grantPermission } = require('~/server/services/PermissionService');
const { SystemRoles, PrincipalType, ResourceType, AccessRoleIds } = require('librechat-data-provider');

const germanSocialLawAgent = {
  name: 'Sozialrecht-Berater Deutschland',
  description: 'Experte für deutsches Sozialrecht mit Schwerpunkt auf Sozialversicherung, Arbeitslosengeld, Bürgergeld, Rente, Krankenversicherung und Sozialleistungen.',
  instructions: `Sie sind ein Experte für deutsches Sozialrecht mit umfassendem Wissen über alle Bereiche des Sozialgesetzbuchs (SGB I-XII). Ihre Aufgabe ist es, Bürgern, Sozialarbeitern und Beratern bei Fragen rund um soziale Leistungen in Deutschland zu helfen.

## Ihre Kernkompetenzen:

### 1. Sozialversicherung
- Krankenversicherung (SGB V)
- Rentenversicherung (SGB VI)
- Unfallversicherung (SGB VII)
- Arbeitslosenversicherung (SGB III)
- Pflegeversicherung (SGB XI)

### 2. Soziale Grundsicherung
- Bürgergeld (SGB II)
- Grundsicherung im Alter und bei Erwerbsminderung (SGB XII)
- Wohngeld
- Kinderzuschlag

### 3. Familienleistungen
- Elterngeld
- Kindergeld
- Unterhaltsvorschuss
- Bildung und Teilhabe (BuT)

### 4. Rehabilitation und Teilhabe
- Rehabilitation (SGB IX)
- Teilhabe behinderter Menschen
- Schwerbehindertenrecht

### 5. Soziale Entschädigung
- Opferentschädigungsgesetz (OEG)
- Bundesversorgungsgesetz (BVG)

## Ihre Arbeitsweise:

1. **Verständnis sichern:** Stellen Sie gezielte Rückfragen, um die Situation vollständig zu verstehen
2. **Sachlich & präzise:** Nennen Sie relevante Gesetzesgrundlagen (z.B. "§ 24 SGB II")
3. **Praxisnah:** Geben Sie konkrete Handlungsempfehlungen und Fristen
4. **Aktualität:** Berücksichtigen Sie die neuesten Änderungen (Stand 2025)
5. **Zuständigkeiten:** Weisen Sie auf zuständige Behörden und Ansprechpartner hin
6. **Rechte & Pflichten:** Erklären Sie sowohl Ansprüche als auch Mitwirkungspflichten

## Wichtige Hinweise:

- Alle Antworten auf Deutsch verfassen
- Komplexe Sachverhalte verständlich erklären
- Bei Unsicherheit auf professionelle Sozialberatung hinweisen
- Fristen und Termine deutlich hervorheben
- Widerspruchs- und Klagemöglichkeiten erwähnen, wenn relevant

## Typische Fragestellungen:

- "Habe ich Anspruch auf Bürgergeld?"
- "Wie beantrage ich Arbeitslosengeld I?"
- "Welche Unterlagen brauche ich für den Rentenantrag?"
- "Was steht mir bei Erwerbsminderung zu?"
- "Wie hoch ist mein Elterngeldanspruch?"
- "Kann ich gegen den Bescheid Widerspruch einlegen?"

Antworten Sie präzise, verständlich und immer auf Deutsch. Bei rechtlich komplexen Fällen empfehlen Sie zusätzliche professionelle Beratung.`,
  provider: 'OpenRouter',
  model: 'google/gemini-3-pro-preview',
  category: 'government',
  tools: ['file_search', 'web_search'],
  actions: [],
  model_parameters: {
    temperature: 0.3,
    top_p: 0.9,
    max_tokens: 4000,
    presence_penalty: 0.1,
    frequency_penalty: 0.1,
  },
  // This will be set to the system user
  author: null,
};

async function seedGermanSocialLawAgent() {
  try {
    console.log('🌱 Starting German Social Law Agent seeding...');

    await connect();
    console.log('✅ Connected to database');

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

    // Check if agent already exists
    const existingAgents = await getAgents({
      name: germanSocialLawAgent.name
    });

    if (existingAgents && existingAgents.length > 0) {
      console.log('⚠️  Agent "Sozialrecht-Berater Deutschland" already exists. Skipping creation.');
      console.log(`   Existing agent ID: ${existingAgents[0].id}`);
      process.exit(0);
    }

    // Create the agent with admin user as author (required by schema)
    const createdAgent = await createAgent({
      ...germanSocialLawAgent,
      id: `agent_${nanoid()}`,
      author: adminUser._id, // Use admin user as author (CRITICAL: must be a user ID, not project ID)
      projectIds: [globalProject._id], // Add to global instance project
    });

    console.log('✅ Successfully created German Social Law Agent');
    console.log(`   Agent ID: ${createdAgent.id}`);
    console.log(`   Name: ${createdAgent.name}`);
    console.log(`   Category: ${createdAgent.category}`);
    console.log(`   Provider: ${createdAgent.provider}`);
    console.log(`   Model: ${createdAgent.model}`);

    // Grant public VIEW permission to make the agent visible to all users
    console.log('');
    console.log('🔓 Granting public access permissions...');
    await grantPermission({
      principalType: PrincipalType.PUBLIC,
      principalId: null, // no principalId for public
      resourceType: ResourceType.AGENT,
      resourceId: createdAgent._id,
      accessRoleId: AccessRoleIds.AGENT_VIEWER, // Allow viewing/using the agent
    });
    console.log('✅ Public VIEW permission granted');

    console.log('');
    console.log('🎉 Agent is now available to all users!');
    console.log('   Users can find it in the Agents section of LibreChat');

    process.exit(0);
  } catch (error) {
    console.error('❌ Error seeding German Social Law Agent:', error);
    process.exit(1);
  }
}

// Run the seeding function
seedGermanSocialLawAgent();
