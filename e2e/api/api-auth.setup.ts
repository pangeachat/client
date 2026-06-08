
import fs from "fs";
import path from "path";
import { test, expect } from "@playwright/test";

/**
 * Authentication setup - Matrix login via HTTP API, saves auth state for API tests.
 *
 * Uses environment variables from .env (local) or AWS Secrets Manager (CI):
 * - TEST_MATRIX_USERNAME: Matrix username (localpart, no @ or domain)
 * - TEST_MATRIX_PASSWORD: Password
 */

const authFile = path.join(__dirname, ".auth", "api-token.json");

test("API authentication", async ({ request }) => {
    const response = await request.post("https://matrix.staging.pangea.chat/_matrix/client/v3/login", {
        data: {
            identifier: {
                type: "m.id.user",
                user: process.env.TEST_MATRIX_USERNAME,
            },
            password: process.env.TEST_MATRIX_PASSWORD,
            type: "m.login.password"
        }
    });
    
    await expect(response.ok()).toBeTruthy();
    await expect(response.status()).toBe(200);

    // Save authentication state
    const loginInfo = await response.json();
    fs.writeFileSync(authFile, JSON.stringify({ loginInfo }));
    await request.dispose();
});