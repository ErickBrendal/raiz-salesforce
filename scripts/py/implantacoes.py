"""Le os JSON de `sf project deploy report` e gera o CSV de RAIZ_Implantacao__c.
Uso: python3 implantacoes.py <pasta_json> <saida.csv> <id=onda> ...  (so leitura de arquivos)"""
import csv, glob, json, sys
pasta, saida = sys.argv[1], sys.argv[2]
ondas = dict(a.split('=', 1) for a in sys.argv[3:])
linhas, pulados = [], []
for f in sorted(glob.glob(pasta + '/dep-*.json')):
    try:
        r = json.load(open(f)).get('result') or {}
    except Exception:
        pulados.append((f, 'json invalido')); continue
    did = r.get('id')
    if not did:
        pulados.append((f, 'sem resultado (deploy antigo ou inexistente)')); continue
    if str(r.get('checkOnly')).lower() == 'true':
        pulados.append((did, 'validacao (dry-run), nao e implantacao')); continue
    ok = int(r.get('numberTestsCompleted') or 0)
    err = int(r.get('numberTestErrors') or 0)
    linhas.append({
        'Deploy_Id__c': did,
        'Org__c': 'Developer Edition (alias radar)',
        'Onda__c': ondas.get(did, ''),
        'Executado_Em__c': r.get('completedDate') or '',
        'Componentes__c': r.get('numberComponentsDeployed') or 0,
        'Testes_Executados__c': ok + err,
        'Testes_Aprovados__c': ok,
        'Resultado__c': 'Sucesso' if str(r.get('success')).lower() == 'true' else 'Falha',
        'Origem__c': 'sf CLI',
    })
with open(saida, 'w', newline='') as o:
    w = csv.DictWriter(o, lineterminator='\n', fieldnames=['Deploy_Id__c', 'Org__c', 'Onda__c', 'Executado_Em__c', 'Componentes__c', 'Testes_Executados__c', 'Testes_Aprovados__c', 'Resultado__c', 'Origem__c'])
    w.writeheader(); w.writerows(linhas)
print('RAIZ IMPLANTACOES: registradas=%d puladas=%d' % (len(linhas), len(pulados)))
for p in pulados: print('  pulado:', p[0].split('/')[-1], '-', p[1])
