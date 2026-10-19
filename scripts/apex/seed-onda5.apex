// =====================================================================
// RAIZ Onda 5 — documentos de demonstracao no Knowledge Hub (ficticios).
// Idempotente: so cria documento para processo que ainda nao tem documento.
// Publicados so em processos que JA estao com registro atualizado, para a
// carga nao mexer nos indicadores. Nao altera processos.
// =====================================================================
String PROJ = RaizKnowledgeService.PROJETO_RAIZ;
List<Project__c> pj = [SELECT Id FROM Project__c WHERE Name = :PROJ LIMIT 1];
if (pj.isEmpty()) { pj.add(new Project__c(Name = PROJ, Description__c = 'Projeto de demonstracao do Knowledge Hub RAIZ (dados ficticios).')); insert pj; }
Id projId = pj[0].Id;

Set<Id> comDoc = new Set<Id>();
for (Business_Rule__c d : [SELECT Processo_Critico__c FROM Business_Rule__c WHERE Processo_Critico__c != null]) comDoc.add(d.Processo_Critico__c);

List<Processo_Critico__c> atualizados = new List<Processo_Critico__c>();
List<Processo_Critico__c> outros = new List<Processo_Critico__c>();
for (Processo_Critico__c p : [SELECT Id, Name, Criticidade__c, Area__c, Atualizado__c FROM Processo_Critico__c ORDER BY Name]) {
    if (comDoc.contains(p.Id)) continue;
    if (p.Atualizado__c) atualizados.add(p); else outros.add(p);
}
Map<String, String> crit = new Map<String, String>{ 'Critico' => 'Critica', 'Alto' => 'Alta', 'Medio' => 'Media', 'Baixo' => 'Baixa' };
Map<String, String> dom = new Map<String, String>{ 'Fiscal' => 'Fiscal', 'Comercial' => 'Comercial', 'Logistica' => 'Logistica', 'TI' => 'Integracao' };

List<Business_Rule__c> docs = new List<Business_Rule__c>();
List<String> plano = new List<String>();
Integer pub = 0;
for (Processo_Critico__c p : atualizados) { if (pub == 2) break; plano.add(p.Id + ':Publicada'); pub++; }
List<String> resto = new List<String>{ 'Aprovada', 'Aprovada', 'Em Analise', 'Em Analise', 'Draft', 'Draft', 'Draft' };
Integer k = 0;
for (Processo_Critico__c p : outros) { if (k == resto.size()) break; plano.add(p.Id + ':' + resto[k]); k++; }

Map<Id, Processo_Critico__c> todos = new Map<Id, Processo_Critico__c>(atualizados);
todos.putAll(outros);
Integer emAnalise = 0;
for (String item : plano) {
    Id pid = Id.valueOf(item.substringBefore(':'));
    String st = item.substringAfter(':');
    Processo_Critico__c p = todos.get(pid);
    Business_Rule__c d = new Business_Rule__c(
        Title__c = ('Registro — ' + p.Name).left(255), Status__c = st,
        Criticality__c = crit.containsKey(p.Criticidade__c) ? crit.get(p.Criticidade__c) : 'Media',
        Domain__c = dom.containsKey(p.Area__c) ? dom.get(p.Area__c) : 'Outro',
        Processo_Critico__c = p.Id, Project__c = projId, Keywords__c = 'DEMO-RAIZ-KH');
    Boolean completo = (st == 'Publicada' || st == 'Aprovada' || (st == 'Em Analise' && emAnalise++ == 0));
    if (completo || st == 'Em Analise') {
        d.Proposito_Documento__c = '<p>Registrar como o processo "' + p.Name + '" é executado, para que uma segunda pessoa consiga fazê-lo sem ajuda. Conteúdo fictício de demonstração.</p>';
        d.Descricao_Demanda__c = '<p>Passo a passo, entradas, saídas, sistemas envolvidos e exceções conhecidas.</p>';
    }
    if (completo) {
        d.Criterios_Aceite__c = '<ul><li>Uma segunda pessoa executa o processo com o registro, sem ajuda.</li><li>Exceções principais descritas.</li></ul>';
        d.Cenarios_Teste__c = '<ul><li>Execução assistida com checklist.</li><li>Execução sozinha no ciclo seguinte.</li></ul>';
    }
    if (st == 'Publicada') d.Last_Review_Date__c = Date.today();
    docs.add(d);
}
insert docs;
System.debug(LoggingLevel.ERROR, 'RAIZ SEED ONDA 5: projeto=' + projId + ' documentos criados=' + docs.size() + ' processos que ja tinham documento=' + comDoc.size());
