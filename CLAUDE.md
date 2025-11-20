# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

LibreChat is an all-in-one AI chat platform that integrates multiple LLM providers (OpenAI, Anthropic, Google, Azure, AWS Bedrock, etc.) with advanced features including agents, tools, file handling, web search, and collaborative workflows. The project is organized as a monorepo with separate workspaces for frontend, backend, and shared packages.

**Tech Stack:**
- **Backend:** Node.js, Express, MongoDB (Mongoose), Redis, Passport.js, MeiliSearch
- **Frontend:** React 18, Vite, Recoil/Jotai (state), TanStack React Query, Tailwind CSS, Radix UI
- **Packages:** Shared TypeScript libraries for data models, API clients, and UI components

## Development Commands

### Initial Setup
```bash
# Install dependencies (use Node.js 20.x)
npm ci

# Build shared packages (required before running app)
npm run build:data-provider
npm run build:data-schemas
npm run build:api
npm run build:client-package

# Or build all packages at once
npm run build:packages
```

### Running the Application
```bash
# Start backend (production mode)
npm run backend

# Start backend (development mode with hot reload)
npm run backend:dev

# Start frontend (development mode)
npm run frontend:dev

# Build frontend for production
npm run frontend
```

### Testing

**Backend Tests:**
```bash
# Run all backend tests
npm run test:api

# Run backend tests in CI mode
cd api && npm run test:ci

# Run backend tests with Bun (alternative)
npm run b:test:api
```

**Frontend Tests:**
```bash
# Run all frontend tests
npm run test:client

# Run frontend tests in CI mode
cd client && npm run test:ci

# Run frontend tests with Bun (alternative)
npm run b:test:client
```

**End-to-End Tests:**
```bash
# Run E2E tests (requires local setup, see CONTRIBUTING.md)
npm run e2e

# Run E2E tests in headed mode (shows browser)
npm run e2e:headed

# Run accessibility tests
npm run e2e:a11y

# Debug E2E tests
npm run e2e:debug
```

### Linting and Formatting
```bash
# Run ESLint
npm run lint

# Fix ESLint errors automatically
npm run lint:fix

# Format code with Prettier
npm run format
```

### Building Individual Packages
```bash
# Build data-provider package
npm run build:data-provider

# Build data-schemas package
npm run build:data-schemas

# Build api package
npm run build:api

# Build client package
npm run build:client-package

# Build frontend client
npm run build:client
```

### User Management Commands
```bash
# Create a new user
npm run create-user

# List all users
npm run list-users

# Reset user password
npm run reset-password

# Ban a user
npm run ban-user

# Delete a user
npm run delete-user

# Add balance to user account
npm run add-balance

# List user balances
npm run list-balances

# Show user statistics
npm run user-stats
```

### Database Migrations
```bash
# Migrate agent permissions (dry run)
npm run migrate:agent-permissions:dry-run

# Migrate agent permissions
npm run migrate:agent-permissions

# Migrate prompt permissions (dry run)
npm run migrate:prompt-permissions:dry-run

# Migrate prompt permissions
npm run migrate:prompt-permissions
```

## Architecture Overview

### Monorepo Structure

**Workspaces:**
- `/api` - Backend Express server (@librechat/backend)
- `/client` - Frontend React application (@librechat/frontend)
- `/packages/data-provider` - Shared data services and API clients
- `/packages/data-schemas` - Mongoose schemas and database models
- `/packages/api` - MCP (Model Context Protocol) services and agent runtime
- `/packages/client` - Reusable React components library

### Backend Architecture

**Server Entry:** [api/server/index.js](api/server/index.js)

**Request Flow:**
```
Routes → Middleware → Controllers → Services → Models → Database
```

**Key Routes:**
- `/api/auth` - Authentication endpoints
- `/api/agents` - Agent management and chat
- `/api/convos` - Conversation management
- `/api/messages` - Message CRUD operations
- `/api/files` - File upload/download
- `/api/assistants` - OpenAI Assistants API
- `/api/prompts` - Prompt management
- `/api/config` - Configuration endpoints
- `/api/mcp` - Model Context Protocol
- `/api/roles` - Role-based access control
- `/api/permissions` - Resource permissions

**Middleware Pipeline:**
- Authentication: JWT, Local, LDAP, OAuth strategies
- Authorization: Role-based access control, resource permissions
- Rate limiting: IP-based, user-based, concurrent message limiting
- Validation: Message validation, model validation, image request validation
- Security: Ban checking, text moderation, mongo sanitization

**Database Models** (in `packages/data-schemas/src/models/`):
- User, Agent, Conversation, Message, File, Assistant, Preset, Prompt, Role, Transaction, Balance, Project, Memory

### Frontend Architecture

**Entry:** [client/src/main.jsx](client/src/main.jsx) → [client/src/App.jsx](client/src/App.jsx)

**State Management Strategy:**
- **Recoil Atoms** ([client/src/store/](client/src/store/)): Global application state
- **Jotai Atoms:** Atomic state for simpler pieces
- **React Query:** Server state management and caching
- **Context Providers** ([client/src/Providers/](client/src/Providers/)): Feature-specific state (AgentsContext, ChatFormContext, etc.)

**Component Organization** ([client/src/components/](client/src/components/)):
```
/Agents       - Agent marketplace, creation, configuration
/Chat         - Main chat interface
/Messages     - Message rendering and interactions
/Input        - Chat input with file uploads, voice
/SidePanel    - Conversation history, settings
/Endpoints    - Endpoint configuration panels
/Auth         - Login, registration, 2FA
/Files        - File management UI
/Prompts      - Prompt library
/MCP          - Model Context Protocol UI
/Artifacts    - Code execution artifacts
```

### Agent System Architecture

**Agent Execution Flow:**
1. Agent definition stored in MongoDB with versioning
2. Agent initialization resolves tool capabilities (built-in + MCP)
3. Agent runtime executes via provider client (OpenAI, Anthropic, etc.)
4. Streaming response sent to client via SSE

**Tool System:**
- **Built-in Tools:** `execute_code`, `file_search`, `web_search`
- **MCP Tools:** Dynamically loaded from MCP servers
- **Actions:** User-defined custom tool integrations

**MCP Integration** ([packages/api/src/mcp/](packages/api/src/mcp/)):
- MCPManager manages MCP server connections
- UserConnectionManager handles per-user MCP server instances
- OAuth support for MCP servers requiring authentication

**Agent Collaboration:**
- Agents can call other agents via `edges` configuration
- Supports handoff patterns and multi-agent workflows

### LLM Provider Abstraction

**Base Client Pattern** ([api/app/clients/BaseClient.js](api/app/clients/BaseClient.js)):
```javascript
class BaseClient {
  setOptions()        // Configure model parameters
  buildMessages()     // Format messages for provider
  sendCompletion()    // Execute completion request
  recordTokenUsage()  // Track usage and costs
  handleStreamData()  // Process streaming responses
}
```

**Provider Implementations:**
- OpenAIClient - OpenAI API (including Azure)
- AnthropicClient - Claude API
- GoogleClient - Gemini/Vertex AI
- OllamaClient - Local Ollama models

### Configuration System

**Primary Configuration:** `librechat.yaml` (version 1.2.1)

**Configuration Loading** ([api/server/services/Config/](api/server/services/Config/)):
1. Load environment variables from `.env`
2. Parse `librechat.yaml`
3. Load endpoint configurations
4. Load model specifications
5. Merge with defaults
6. Cache configuration

**Configurable Aspects:**
- File storage strategies (local, S3, Firebase) - per file type
- Endpoint configurations (OpenAI, Anthropic, Google, etc.)
- Model specifications with capabilities
- UI features and customization
- Authentication providers (OAuth, LDAP, SAML)
- Rate limiting and balance/credit system
- MCP server configurations

### File Storage System

**Multi-Strategy Storage** ([api/server/services/Files/strategies/](api/server/services/Files/strategies/)):
- **Local:** File system storage
- **S3:** AWS S3 compatible storage
- **Firebase:** Firebase Cloud Storage

**Per-File-Type Configuration:**
```yaml
fileStrategy:
  avatar: "s3"      # User/agent avatars
  image: "firebase" # Chat images
  document: "local" # PDFs, text files
```

### Authentication & Authorization

**Authentication Strategies** ([api/strategies/](api/strategies/)):
- JWT, Local (username/password), LDAP, Social Logins (Google, GitHub, Discord, Facebook, Apple), OpenID Connect, SAML

**Authorization Model:**
- **Resource-Based Access Control:** Resources (Agents, Prompts, Conversations, Files)
- **Permissions:** VIEW, USE, EDIT, DELETE, SHARE, COLLABORATE
- **Access Levels:** Public, Private, Group-specific, Role-specific
- **Role System:** System roles (Admin, User) + custom role definitions

**Permission Checking Flow:**
```
Request → requireJwtAuth → checkBan → checkAgentAccess → checkAgentResourceAccess → Controller
```

### Real-time Communication

**Server-Sent Events (SSE):**
- Primary mechanism for streaming LLM responses
- Event types: message, token, tool_call, error, final
- Abort handling for cancelled requests
- Client-side SSE handling in [client/src/hooks/SSE/](client/src/hooks/SSE/)

**WebSocket Support:**
- Real-time notifications
- Presence indicators
- Multi-conversation updates

### Caching Strategy

**Multi-Layer Caching:**
- **Redis Cache:** Session storage, rate limit counters, MCP tool definitions, model metadata, configuration cache
- **React Query Cache:** Client-side API response caching with stale-while-revalidate pattern
- **MongoDB Indexes:** Compound indexes on frequently queried fields
- **MeiliSearch:** Full-text search over conversations and messages with real-time synchronization

## Development Workflow

### Before Starting Work
```bash
# Update main branch with latest commits
npm run update

# Reinstall packages after pulling changes
npm run reinstall

# Restart ESLint server in VS Code after reinstalling
# Command: "ESLint: Restart ESLint Server"
```

### Making Changes

1. **Clear browser storage:** Clear localStorage and cookies before and after changes
2. **Run linting:** `npm run lint` (or rely on husky pre-commit checks)
3. **For frontend changes:** Compile TypeScript to check for errors:
   ```bash
   cd client && npm run build
   ```
4. **Run tests:** Always run relevant tests before committing
   ```bash
   npm run test:api    # Backend tests
   npm run test:client # Frontend tests
   npm run e2e         # Integration tests
   ```

### Git Commit Guidelines

Follow semantic commit format:
```
feat: add hat wobble
^--^  ^------------^
|     |
|     +-> Summary in present tense
|
+-------> Type: feat, fix, refactor, docs, chore, style, test
```

Use slash-based branch names: `new/feature/x`, `fix/bug/y`, `refactor/component/z`

## Important Patterns & Conventions

### Shared Package Build Order
Always build packages in this order (dependencies matter):
1. `build:data-provider`
2. `build:data-schemas`
3. `build:api`
4. `build:client-package`

### State Management Patterns

**Use Recoil for:**
- Global UI state (settings, theme, navigation)
- Endpoint and model selection state
- Message families and relationships

**Use React Query for:**
- All API data fetching
- Server-side state caching
- Background refetching
- Optimistic updates

**Use Context for:**
- Feature-specific state (AgentsContext, ChatFormContext)
- State that needs to be accessed deeply in component trees

### File Organization

**Backend:**
- Controllers in [api/server/controllers/](api/server/controllers/)
- Routes in [api/server/routes/](api/server/routes/)
- Middleware in [api/server/middleware/](api/server/middleware/)
- Services in [api/server/services/](api/server/services/)
- Models in [packages/data-schemas/src/models/](packages/data-schemas/src/models/)

**Frontend:**
- Feature-based components in [client/src/components/](client/src/components/)
- Hooks in [client/src/hooks/](client/src/hooks/)
- Store (state) in [client/src/store/](client/src/store/)
- Utils in [client/src/utils/](client/src/utils/)

### Testing Patterns

**Backend Unit Tests:**
- Test files: `*.spec.js` alongside source files
- Use MongoDB Memory Server for isolated database tests
- Mock external services (Redis, MeiliSearch, LLM APIs)

**Frontend Unit Tests:**
- Test files: `*.test.tsx` alongside components
- Use React Testing Library for component tests
- Mock API calls with MSW (Mock Service Worker)

**E2E Tests:**
- Located in [e2e/specs/](e2e/specs/)
- Use Playwright for browser automation
- Test critical user journeys

## Common Issues & Solutions

### Package Build Errors
If you encounter build errors in packages:
```bash
# Clean and rebuild all packages
npm run reinstall
npm run build:packages
```

### TypeScript Errors
If TypeScript errors appear after pulling changes:
```bash
# Rebuild packages to regenerate type definitions
npm run build:packages

# Restart ESLint server in VS Code
# Command: "ESLint: Restart ESLint Server"
```

### Database Connection Issues
Ensure MongoDB is running and connection string is correct in `.env`:
```env
MONGO_URI=mongodb://localhost:27017/LibreChat
```

### Frontend Not Reflecting Changes
Clear browser cache and rebuild:
```bash
# Clear localStorage and cookies in browser
# Then rebuild frontend
cd client && npm run build
```

## Testing Requirements

Per user instructions in `.claude/CLAUDE.md`, always:
1. Run tests before applying changes: `npm run test:api` and `npm run test:client`
2. Run tests before marking work as done
3. Resolve all test issues
4. Practice test-driven development (TDD) when appropriate

## Environment & Configuration

**Required Environment Variables:**
- `MONGO_URI` - MongoDB connection string
- `JWT_SECRET` - Secret for JWT token signing
- `REDIS_URI` - Redis connection string (optional but recommended)
- `MEILI_HOST` - MeiliSearch host (optional, for search features)

**Optional Configuration:**
- `librechat.yaml` - Main configuration file (copy from `librechat.example.yaml`)
- `.env` - Environment variables (copy from `.env.example`)

**Note:** Per user instructions, never delete files already in `.gitignore` (they won't be committed anyway).

## Additional Resources

- **Documentation:** https://docs.librechat.ai
- **Contributing Guide:** [.github/CONTRIBUTING.md](.github/CONTRIBUTING.md)
- **Discord Community:** https://discord.librechat.ai
- **Issues:** https://github.com/danny-avila/LibreChat/issues
