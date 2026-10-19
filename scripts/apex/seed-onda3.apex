// =====================================================================
// RAIZ Onda 3 — planos de demonstracao IDEMPOTENTES (cria so o que falta).
// Cria um plano "Habilitar substituto" para cada processo em que o declarado
// diz 2 aptos e a evidencia diz 1 (as divergencias propositais da Onda 1).
// Um deles fica com data alvo vencida, para mostrar o estado "atrasado".
// Dados ficticios. Nao altera processos nem habilitacoes.
// =====================================================================
List<Processo_Critico__c> alvos = [
    SELECT Id, Name, Risco_Score__c, Estado_Cobertura__c, Aptos_Efetivos__c,
           (SELECT Profissional__c FROM Habilitacoes__r WHERE Status__c = 'Apto' AND Papel__c = 'Titular' LIMIT 1)
    FROM Processo_Critico__c
    WHERE Pessoas_Aptas__c = 2
    ORDER BY Name
];
// Idempotente de verdade: so CRIA o que ainda nao existe. Plano de demonstracao
// ja criado (chave RAIZ-PLANO-) nao e sobrescrito, e processo que ja tem plano
// aberto criado pelo usuario fica de fora.
Set<String> chavesExistentes = new Set<String>();
Set<Id> comPlanoAberto = new Set<Id>();
for (Plano_Mitigacao__c pl : [SELECT Chave_Externa__c, Processo__c, Status__c FROM Plano_Mitigacao__c]) {
    if (pl.Chave_Externa__c != null) chavesExistentes.add(pl.Chave_Externa__c);
    if (RaizMitigationService.ABERTOS.contains(pl.Status__c)) comPlanoAberto.add(pl.Processo__c);
}
Integer jaExistiam = 0;
for (Integer k = alvos.size() - 1; k >= 0; k--) {
    Processo_Critico__c p = alvos[k];
    if (p.Aptos_Efetivos__c != 1) { alvos.remove(k); continue; }
    if (chavesExistentes.contains('RAIZ-PLANO-' + p.Id) || comPlanoAberto.contains(p.Id)) { alvos.remove(k); jaExistiam++; }
}
Date hoje = Date.today();
List<Plano_Mitigacao__c> planos = new List<Plano_Mitigacao__c>();
Integer i = 0;
for (Processo_Critico__c p : alvos) {
    Id resp = p.Habilitacoes__r.isEmpty() ? null : p.Habilitacoes__r[0].Profissional__c;
    planos.add(new Plano_Mitigacao__c(
        Chave_Externa__c = 'RAIZ-PLANO-' + p.Id,
        Name = ('Habilitar substituto — ' + p.Name).left(80),
        Processo__c = p.Id,
        Objetivo__c = RaizMitigationService.HABILITAR,
        Status__c = RaizMitigationService.EM_EXECUCAO,
        Responsavel__c = resp,
        Data_Alvo__c = (i == 0) ? hoje.addDays(-5) : hoje.addDays(20 + 10 * i),
        Score_Inicial__c = p.Risco_Score__c,
        Estado_Inicial__c = p.Estado_Cobertura__c));
    i++;
}
insert planos;

List<Acao_Mitigacao__c> acoes = new List<Acao_Mitigacao__c>();
i = 0;
for (Plano_Mitigacao__c pl : planos) {
    Integer ordem = 1;
    for (List<Object> t : RaizMitigationService.modelo(RaizMitigationService.HABILITAR)) {
        Boolean feita = (ordem == 1);
        acoes.add(new Acao_Mitigacao__c(
            Chave_Externa__c = 'RAIZ-ACAO-' + pl.Processo__c + '-' + ordem,
            Plano__c = pl.Id, Name = (String) t[0], Tipo__c = (String) t[1],
            Responsavel__c = pl.Responsavel__c,
            Prazo__c = (i == 0) ? hoje.addDays(-12 + 4 * ordem) : hoje.addDays((Integer) t[2]),
            Status__c = feita ? 'Concluida' : 'A fazer',
            Ordem__c = ordem));
        ordem++;
    }
    i++;
}
insert acoes;
System.debug(LoggingLevel.ERROR, 'RAIZ SEED ONDA 3: planos criados=' + planos.size() + ' acoes criadas=' + acoes.size() + ' ja existiam=' + jaExistiam);
