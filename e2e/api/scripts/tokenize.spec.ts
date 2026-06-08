import fs from "fs";
import path from "path";
import { test, expect } from "@playwright/test";
import { authHeaderValues } from "../helpers";

/**
 * Tokenize integration test
 *
 * Triggers:
 * - lib/pangea/tokens/**
 */

test.describe("Tokenize", () => {
  test("tokenize request and response should be valid", async ({ request
  }) => {
    // Use client/lib/pangea/tokens/mock_tokenize_request.json for request data
    const filePath = path.resolve(__dirname, '../../../lib/pangea/tokens/mock_tokenize_request.json');
    const fileContent = fs.readFileSync(filePath, 'utf-8');
    const data = JSON.parse(fileContent);

    const response = await request.post("https://api.staging.pangea.chat/choreo/tokenize", {
        headers: authHeaderValues(),
        data: data,
    });

    await expect(response.ok()).toBeTruthy();
    await expect(response.status()).toBe(200);

    // Save authentication state
    const tokenizeInfo = JSON.parse(await response.json());

  });
});