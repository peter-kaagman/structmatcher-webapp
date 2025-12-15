import os
import json
import random
import string
from pathlib import Path
from collections import defaultdict

def random_guid():
    # Generate a fake GUID-like string
    return ''.join(random.choices('abcdef' + string.digits, k=8)) + '-' + \
           ''.join(random.choices('abcdef' + string.digits, k=4)) + '-' + \
           ''.join(random.choices('abcdef' + string.digits, k=4)) + '-' + \
           ''.join(random.choices('abcdef' + string.digits, k=4)) + '-' + \
           ''.join(random.choices('abcdef' + string.digits, k=12))

def make_email(given, family):
    return f"{given.lower()}.{family.lower()}@example.com"

def make_mailnickname(given, family):
    return (given[0] + family[:2]).upper()

def make_initials(given):
    return given[0].upper() + '.'

def clean_filename(name):
    return ''.join(c for c in name if c.isalnum())

def load_json_files(folder):
    files = list(Path(folder).glob('*.json'))
    data = {}
    for f in files:
        with open(f, encoding='utf-8') as fp:
            data[f] = json.load(fp)
    return data

def generate_fake_names(n):
    # Simple list, can be expanded
    first_names = ["Jan", "Piet", "Kees", "Anna", "Sanne", "Tom", "Lisa", "Bram", "Eva", "Noor", "Daan", "Fleur", "Koen", "Lars", "Mila", "Rik", "Tess", "Joris", "Lieke", "Gijs", "Sophie", "Finn", "Julia", "Niels", "Sara", "Luuk", "Emma", "Max", "Lotte", "Thijs", "Yara", "Sem", "Zoë", "Jelle", "Isa", "Stijn", "Mara", "Ruben", "Fenna", "Timo", "Nina"]
    last_names = ["Jansen", "deVries", "Bakker", "Visser", "Smit", "Meijer", "Mulder", "Bos", "Vos", "Peters", "Hendriks", "Dekker", "Brouwer", "deBoer", "Kok", "Jacobs", "Sanders", "vanDijk", "vanLeeuwen", "deGroot", "Vermeulen", "Kramer", "Willems", "vanDam", "Schouten", "Dijkstra", "Hermans", "vanWijk", "Molenaar", "deJong", "van den Berg"]
    used = set()
    result = []
    while len(result) < n:
        f = random.choice(first_names)
        l = random.choice(last_names)
        if (f, l) not in used:
            used.add((f, l))
            result.append((f, l))
    return result

def main():
    input_folder = "./TestPersons/blaat"
    output_folder = "./TestPersons/blaat_anon"
    os.makedirs(output_folder, exist_ok=True)
    files = list(Path(input_folder).glob('*.json'))
    n = len(files)
    fake_names = generate_fake_names(n)
    fake_numbers = random.sample(range(900000, 900000 + n * 2), n)
    guid_map = {}
    personid_map = {}
    extid_map = {}
    name_map = {}
    # 1. Eerste ronde: mapping opbouwen
    print(f"Start met anonimiseren van {n} bestanden...")
    valid_files = []
    file_encodings = {}
    for idx, f in enumerate(files):
        print(f"[Stap 1/{n}] Mapping opbouwen voor bestand {idx+1} van {n}: {f.name}")
        data = None
        encoding_used = None
        for enc in ['utf-8', 'utf-16', 'utf-16le', 'utf-16be', 'latin-1']:
            try:
                with open(f, encoding=enc) as fp:
                    data = json.load(fp)
                encoding_used = enc
                break
            except UnicodeDecodeError:
                continue
            except Exception as e:
                print(f"Waarschuwing: Bestand {f.name} kan niet worden ingelezen met encoding {enc}: {e}")
                data = None
                break
        if data is None:
            print(f"Waarschuwing: Bestand {f.name} kan niet worden gelezen met utf-8, utf-16 of latin-1 en wordt overgeslagen.")
            continue
        print(f"Inhoud van data voor {f.name} (encoding: {encoding_used}): {data}")
        given, family = fake_names[idx]
        display = f"{given} {family}"
        initials = make_initials(given)
        mail = make_email(given, family)
        mailnick = make_mailnickname(given, family)
        number = str(fake_numbers[idx])
        guid = random_guid()
        personid_map[data.get('PersonId')] = guid
        extid_map[data.get('ExternalId')] = number
        name_map[data.get('PersonId')] = {
            'DisplayName': display,
            'GivenName': given,
            'FamilyName': family,
            'Initials': initials,
            'Mail': mail,
            'MailNickname': mailnick,
            'Number': number,
            'GUID': guid
        }
        valid_files.append(f)
        file_encodings[f] = encoding_used
    # 2. Tweede ronde: vervangen en schrijven
    for idx, f in enumerate(valid_files):
        print(f"[Stap 2/{len(valid_files)}] Anonimiseren en schrijven van bestand {idx+1} van {len(valid_files)}: {f.name}")
        encoding = file_encodings.get(f, 'utf-8')
        try:
            with open(f, encoding=encoding) as fp:
                data = json.load(fp)
        except Exception as e:
            print(f"Waarschuwing: Bestand {f.name} kan niet worden ingelezen in stap 2 (encoding {encoding}): {e}")
            continue
        mymap = name_map[data.get('PersonId')]
        # Hoofdvelden
        data['PersonId'] = mymap['GUID']
        data['ExternalId'] = mymap['Number']
        data['DisplayName'] = f"{mymap['DisplayName']} ({mymap['Number']})"
        if 'UserName' in data:
            data['UserName'] = mymap['Mail']
        if 'Name' in data:
            data['Name']['Initials'] = mymap['Initials']
            data['Name']['GivenName'] = mymap['GivenName']
            data['Name']['NickName'] = mymap['GivenName']
            data['Name']['FamilyName'] = mymap['FamilyName']
        # Accounts
        if 'Accounts' in data:
            for acc in data['Accounts'].values():
                if 'displayName' in acc:
                    acc['displayName'] = mymap['DisplayName']
                if 'employeeId' in acc:
                    acc['employeeId'] = mymap['Number']
                if 'mail' in acc:
                    acc['mail'] = mymap['Mail']
                if 'mailNickname' in acc:
                    acc['mailNickname'] = mymap['MailNickname']
                if 'userPrincipalName' in acc:
                    acc['userPrincipalName'] = mymap['Mail']
                if 'Medewerker' in acc:
                    acc['Medewerker'] = mymap['Number']
                if 'Persoonsnummer' in acc:
                    acc['Persoonsnummer'] = mymap['Number']
                if 'EmailAddresses' in acc:
                    acc['EmailAddresses'] = [f"SMTP:{mymap['Mail']}"]
        # Contact
        if 'Contact' in data:
            for k in ['Personal', 'Business']:
                if k in data['Contact'] and 'Email' in data['Contact'][k]:
                    data['Contact'][k]['Email'] = mymap['Mail']
        # Custom
        if 'Custom' in data:
            if 'MagisterId' in data['Custom']:
                data['Custom']['MagisterId'] = mymap['Number']
            if 'MedewerkersAfkorting' in data['Custom']:
                data['Custom']['MedewerkersAfkorting'] = mymap['MailNickname']
        # GUIDs in top-level
        for k in ['PersonId', 'SystemId']:
            if k in data:
                data[k] = mymap['GUID']
        # Contracts, PrimaryContract, PrimaryManager
        for contract_field in ['Contracts', 'PrimaryContract']:
            if contract_field in data:
                contracts = data[contract_field] if isinstance(data[contract_field], list) else [data[contract_field]]
                for c in contracts:
                    if 'ExternalId' in c:
                        c['ExternalId'] = random_guid()
                    if 'Manager' in c and 'PersonId' in c['Manager']:
                        mid = c['Manager']['PersonId']
                        if mid in name_map:
                            m = name_map[mid]
                            c['Manager']['PersonId'] = m['GUID']
                            c['Manager']['ExternalId'] = m['Number']
                            c['Manager']['DisplayName'] = f"{m['DisplayName']} ({m['Number']})"
                            c['Manager']['Email'] = m['Mail']
        if 'PrimaryManager' in data and 'PersonId' in data['PrimaryManager']:
            mid = data['PrimaryManager']['PersonId']
            if mid in name_map:
                m = name_map[mid]
                data['PrimaryManager']['PersonId'] = m['GUID']
                data['PrimaryManager']['ExternalId'] = m['Number']
                data['PrimaryManager']['DisplayName'] = f"{m['DisplayName']} ({m['Number']})"
                data['PrimaryManager']['Email'] = m['Mail']
        # Bestandsnaam
        fname = f"{clean_filename(mymap['DisplayName'])}_{str(idx+1).zfill(3)}.json"
        outpath = Path(output_folder) / fname
        try:
            with open(outpath, 'w', encoding='utf-8') as fp:
                json.dump(data, fp, indent=4, ensure_ascii=False)
        except Exception as e:
            print(f"Fout bij schrijven van {outpath}: {e}")
    print(f"Anonimisatie voltooid. Bestanden staan in {output_folder}")

if __name__ == "__main__":
    main()
