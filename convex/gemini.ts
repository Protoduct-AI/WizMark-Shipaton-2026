const GEMINI_ENDPOINT =
    'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

/**
 * Call Gemini API with the given prompt and return the extracted JSON string.
 * Throws on HTTP errors or invalid responses.
 */
export async function callGemini(apiKey: string, prompt: string): Promise<string> {
    const response = await fetch(GEMINI_ENDPOINT, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'x-goog-api-key': apiKey,
        },
        body: JSON.stringify({
            contents: [{ parts: [{ text: prompt }] }],
            tools: [{ google_search: {} }],
            generationConfig: { temperature: 0.1, maxOutputTokens: 2000 },
        }),
    });

    if (!response.ok) {
        throw new Error(`Gemini API error: ${response.status}`);
    }

    const data = await response.json();
    const parts = data?.candidates?.[0]?.content?.parts;
    if (!parts) {
        throw new Error('Invalid Gemini response');
    }

    const textParts = parts
        .filter((p: { text?: string }) => p.text)
        .map((p: { text: string }) => p.text);
    const fullText = textParts[textParts.length - 1] || textParts.join('');

    let jsonString = fullText.trim();
    if (jsonString.startsWith('```')) {
        jsonString = jsonString.replace(/```json/g, '').replace(/```/g, '').trim();
    }

    const startIdx = jsonString.indexOf('{');
    const endIdx = jsonString.lastIndexOf('}');
    if (startIdx !== -1 && endIdx !== -1) {
        jsonString = jsonString.slice(startIdx, endIdx + 1);
    }

    // Validate JSON before returning
    JSON.parse(jsonString);
    return jsonString;
}
