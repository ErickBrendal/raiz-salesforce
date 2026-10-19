// Agenda o job diario de vencimento (05:00, fuso do usuario). Idempotente.
List<CronTrigger> ja = [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name = :RaizHabilitacaoVencimentoJob.NOME];
if (ja.isEmpty()) {
    System.schedule(RaizHabilitacaoVencimentoJob.NOME, '0 0 5 * * ?', new RaizHabilitacaoVencimentoJob());
    System.debug(LoggingLevel.ERROR, 'RAIZ: job agendado.');
} else {
    System.debug(LoggingLevel.ERROR, 'RAIZ: job ja estava agendado (' + ja.size() + ').');
}
// Roda uma vez agora para alinhar o roll-up com a data de hoje.
Database.executeBatch(new RaizHabilitacaoVencimentoJob(), 200);
