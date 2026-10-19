"""Gera evidencias sf CLI (LWC existente e cobertura de Apex) para RAIZ_Evidencia__c.
Uso: python3 evidencias.py <inventario.csv> <lwc.csv> <cobertura.csv> <saida.csv>  (so leitura de arquivos)"""
import csv, sys, datetime
inv, lwc, cob, saida = sys.argv[1:5]
agora = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
itens = list(csv.DictReader(open(inv, encoding='utf-8-sig')))
bundles = {r['DeveloperName'] for r in csv.DictReader(open(lwc, encoding='utf-8-sig'))}
cobert = {}
for r in csv.DictReader(open(cob, encoding='utf-8-sig')):
    nome = r.get('ApexClassOrTrigger.Name')
    c, u = int(r.get('NumLinesCovered') or 0), int(r.get('NumLinesUncovered') or 0)
    if nome: cobert[nome] = (c, u)
out = []
for i in itens:
    api, tipo = i['API_Name__c'], i['Tipo_Componente__c']
    if tipo == 'LWC':
        ok = api in bundles
        out.append((api, 'Metadado na org', ok, 'LightningComponentBundle ' + ('encontrado' if ok else 'não encontrado') + ' (Tooling API).'))
    if tipo in ('Classe Apex', 'Trigger') and api in cobert:
        c, u = cobert[api]
        pct = round(100.0 * c / (c + u)) if c + u else 0
        out.append((api, 'Cobertura', c + u > 0 and pct >= 75, '%d%% de cobertura (%d de %d linhas), ApexCodeCoverageAggregate.' % (pct, c, c + u)))
with open(saida, 'w', newline='') as o:
    w = csv.writer(o, lineterminator='\n')
    w.writerow(['Item__r.API_Name__c', 'Chave__c', 'Tipo__c', 'Origem__c', 'Resultado__c', 'Detalhe__c', 'Verificado_Em__c'])
    for api, tipo, ok, det in out:
        w.writerow([api, (api + '|' + tipo + '|sf CLI')[:255], tipo, 'sf CLI', 'Aprovado' if ok else 'Reprovado', det[:255], agora])
print('RAIZ EVIDENCIAS SF CLI: %d (LWC e cobertura)' % len(out))
