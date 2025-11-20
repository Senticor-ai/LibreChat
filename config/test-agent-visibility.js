/**
 * Playwright test to check agent visibility
 * Run with: node config/test-agent-visibility.js
 */

const { chromium } = require('playwright');

async function testAgentVisibility() {
  let browser;
  try {
    console.log('🚀 Launching browser...');
    browser = await chromium.launch({
      headless: false,
      slowMo: 500
    });

    const context = await browser.newContext();
    const page = await context.newPage();

    // Enable console logging from the page
    page.on('console', msg => console.log('Browser console:', msg.text()));

    // Navigate to LibreChat
    console.log('📍 Navigating to http://localhost:3080/c/new');
    await page.goto('http://localhost:3080/c/new', { waitUntil: 'networkidle' });

    // Wait a bit for the page to fully load
    await page.waitForTimeout(2000);

    // Take a screenshot of the initial state
    await page.screenshot({ path: '/tmp/librechat-initial.png', fullPage: true });
    console.log('📸 Screenshot saved to /tmp/librechat-initial.png');

    // Check if we're on login page
    const loginButton = await page.locator('button:has-text("Sign in")').first();
    const isLoginPage = await loginButton.isVisible().catch(() => false);

    if (isLoginPage) {
      console.log('🔐 Login page detected - need credentials');
      console.log('Please ensure you are logged in or provide credentials');
      await page.screenshot({ path: '/tmp/librechat-login.png' });
      console.log('📸 Login page screenshot saved to /tmp/librechat-login.png');
    } else {
      console.log('✅ Already logged in or no login required');
    }

    // Look for agent-related elements
    console.log('\n🔍 Searching for agent-related UI elements...');

    // Try to find the agent selector or menu
    const agentSelectors = [
      'text=My Agents',
      'text=Sozialrecht-Berater',
      '[data-testid*="agent"]',
      'button:has-text("Agent")',
      '[aria-label*="agent"]',
    ];

    for (const selector of agentSelectors) {
      const element = page.locator(selector).first();
      const isVisible = await element.isVisible().catch(() => false);
      console.log(`  ${selector}: ${isVisible ? '✅ Found' : '❌ Not found'}`);

      if (isVisible) {
        const text = await element.textContent().catch(() => '');
        console.log(`    Text: "${text}"`);
      }
    }

    // Try to click on "My Agents" if visible
    const myAgentsButton = page.locator('text=My Agents').first();
    const myAgentsVisible = await myAgentsButton.isVisible().catch(() => false);

    if (myAgentsVisible) {
      console.log('\n👆 Clicking on "My Agents"...');
      await myAgentsButton.click();
      await page.waitForTimeout(1000);
      await page.screenshot({ path: '/tmp/librechat-agents-menu.png', fullPage: true });
      console.log('📸 Agents menu screenshot saved to /tmp/librechat-agents-menu.png');

      // Check what's in the dropdown/menu
      const menuItems = await page.locator('[role="menuitem"], [role="option"], li').all();
      console.log(`\n📋 Found ${menuItems.length} menu items:`);
      for (let i = 0; i < Math.min(menuItems.length, 10); i++) {
        const text = await menuItems[i].textContent().catch(() => '');
        console.log(`  ${i + 1}. "${text.trim()}"`);
      }
    }

    // Check network requests for agent API calls
    console.log('\n🌐 Checking API requests...');
    page.on('response', async (response) => {
      const url = response.url();
      if (url.includes('/api/agents') || url.includes('/api/config')) {
        console.log(`API Response: ${response.status()} ${url}`);
        if (url.includes('/api/agents')) {
          try {
            const body = await response.json();
            console.log('Agents response:', JSON.stringify(body, null, 2));
          } catch (e) {
            console.log('Could not parse response body');
          }
        }
      }
    });

    // Trigger a refresh to see API calls
    console.log('\n🔄 Refreshing page to capture API calls...');
    await page.reload({ waitUntil: 'networkidle' });
    await page.waitForTimeout(3000);

    console.log('\n✅ Test completed. Check screenshots in /tmp/');
    console.log('Press Ctrl+C to close the browser');

    // Keep browser open for manual inspection
    await page.waitForTimeout(30000);

  } catch (error) {
    console.error('❌ Error during test:', error);
  } finally {
    if (browser) {
      await browser.close();
    }
  }
}

testAgentVisibility();
