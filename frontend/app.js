document.getElementById('uploadForm').addEventListener('submit', async function(e) {
    e.preventDefault();
    const conditionSetFile = document.getElementById('conditionSetFile').files[0];
    const personFile = document.getElementById('personFile').files[0];
    if (!conditionSetFile || !personFile) {
        document.getElementById('result').textContent = 'Selecteer beide bestanden.';
        return;
    }
    const conditionSet = JSON.parse(await conditionSetFile.text());
    const personData = JSON.parse(await personFile.text());
    // Stuur naar backend API
    const response = await fetch('http://localhost:7071/api/TestConditionSet', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ conditionSet, personData })
    });
    const result = await response.text();
    document.getElementById('result').textContent = result;
});
