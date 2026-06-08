import fs from "fs";
import path from "path";

export function authHeaderValues() {
    const fileData = fs.readFileSync(path.resolve(__dirname, '.auth/api-token.json'), 'utf-8');
    const accessToken = JSON.parse(fileData).loginInfo.access_token;
    const cleanedToken = JSON.stringify(accessToken).replaceAll('"', '');

    const headers = {
        "Authorization": "Bearer " + cleanedToken,
        "api_key": process.env.CHOREO_API_KEY,
    }

    return headers;
}