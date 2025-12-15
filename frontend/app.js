// Download functionaliteit voor condition set
document.getElementById('downloadConditionSet').addEventListener('click', function() {
    const editor = document.getElementById('conditionSetEditor');
    let jsonText = editor.value.trim();
    if (!jsonText) {
        alert('Geen condition set om te downloaden.');
        return;
    }
    let filename = 'conditionSet.json';
    try {
        // Beautify JSON indien mogelijk
        const obj = JSON.parse(jsonText);
        jsonText = JSON.stringify(obj, null, 2);
    } catch {}
    const blob = new Blob([jsonText], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
});



const fileInput = document.getElementById('conditionSetFile');
const textarea = document.getElementById('conditionSetEditor');
let editor = null;

// Initialiseer CodeMirror
window.addEventListener('DOMContentLoaded', function() {
    editor = CodeMirror(document.getElementById('codeMirrorEditor'), {
        value: textarea.value,
        mode: { name: 'javascript', json: true },
        lineNumbers: true,
        matchBrackets: true,
        tabSize: 2,
        autofocus: true,
        theme: 'default',
        viewportMargin: Infinity
    });
});

fileInput.addEventListener('change', async function() {
    const file = fileInput.files[0];
    if (!file) return;
    const text = await file.text();
    editor.setValue(text);
});

document.getElementById('uploadForm').addEventListener('submit', async function(e) {
    e.preventDefault();
    // Leeg het resultaatveld vóór elke nieuwe test
    document.getElementById('result').textContent = '';
    let jsonText = editor.getValue().trim();
    if (!jsonText) {
        document.getElementById('result').textContent = 'Voer of upload een ConditionSet JSON in.';
        return;
    }
    let conditionSet;
    try {
        conditionSet = JSON.parse(jsonText);
    } catch {
        document.getElementById('result').textContent = 'Ongeldige JSON in editor.';
        return;
    }
    const maxPersons = parseInt(document.getElementById('maxPersons').value, 10) || 0;
    console.log('conditionSet:', conditionSet);
    console.log('maxPersons:', maxPersons);
    const response = await fetch('http://localhost:7071/api/TestConditionSet', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ conditionSet, maxPersons })
    });
    let resultText = '';
    try {
        const result = await response.json();
        if (Array.isArray(result)) {
            if (result.length === 0) {
                resultText = 'Geen resultaten.';
            } else {
                let matches = result.filter(r => r.Match);
                let errors = result.filter(r => r.Error);
                // Nieuw: aantal matches tonen
                resultText += `<div style="margin-bottom:0.5em;"><b>Aantal matches:</b> ${matches.length}</div>`;
                if (matches.length > 0) {
                    resultText += '<b>Matches:</b><br>';
                    matches.forEach(r => {
                        resultText += `Match gevonden in bestand: <b>${r.File}</b>`;
                        if (r.DisplayName) {
                            resultText += ` (<b>${r.DisplayName}</b>)`;
                        }
                        resultText += `<br>Resultaat: <pre>${JSON.stringify(r.Match, null, 2)}</pre><hr>`;
                    });
                }
                if (errors.length > 0) {
                    resultText += '<b>Fouten:</b><br>';
                    errors.forEach(r => {
                        resultText += `Fout bij verwerken van bestand <b>${r.File}</b>:<br><pre>${r.Error}</pre><hr>`;
                    });
                }
                if (matches.length === 0 && errors.length === 0) {
                    resultText = 'Geen match gevonden.';
                }
            }
        } else if (typeof result === 'string') {
            resultText = result;
        } else {
            resultText = 'Geen match gevonden.';
        }
    } catch {
        resultText = 'Ongeldig antwoord van server.';
    }
    document.getElementById('result').innerHTML = resultText;
});
