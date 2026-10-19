/**
 * RaizTestData — fabrica de dados de teste do Metodo RAIZ.
 *
 * Por que usuario proprio: as consultas usam USER_MODE e FALHAM sem FLS.
 * O usuario que roda o deploy nao necessariamente tem o permission set,
 * entao os testes rodam como um usuario criado aqui, com EBL_RAIZ_Cockpit.
 */
@IsTest
public class RaizTestData {
    public static final String EMAIL_RAIZ = 'raiz.teste@metodo-raiz.demo';
    public static final String EMAIL_SEM = 'raiz.semacesso@metodo-raiz.demo';

    /** Cria (uma vez por teste) o usuario com permission set. Chamar no @TestSetup. */
    public static void criarUsuarios() {
        Id psId = [SELECT Id FROM PermissionSet WHERE Name = 'EBL_RAIZ_Cockpit' LIMIT 1].Id;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<Id> perfis = new List<Id>{ UserInfo.getProfileId() };
            for (Profile p : [SELECT Id FROM Profile WHERE UserLicense.Name = 'Salesforce Platform' ORDER BY Name LIMIT 3]) {
                perfis.add(p.Id);
            }
            User comAcesso = inserirPrimeiro(perfis, EMAIL_RAIZ, 'Raiz Teste', 'raiztst');
            insert new PermissionSetAssignment(AssigneeId = comAcesso.Id, PermissionSetId = psId);

            // Usuario SEM o permission set, para provar que a tela falha com mensagem e nao com branco.
            List<Id> perfisSem = new List<Id>();
            for (Profile p : [
                SELECT Id
                FROM Profile
                WHERE Name IN ('Standard User', 'Minimum Access - Salesforce', 'Standard Platform User')
                ORDER BY Name
            ]) {
                perfisSem.add(p.Id);
            }
            if (!perfisSem.isEmpty()) {
                try {
                    inserirPrimeiro(perfisSem, EMAIL_SEM, 'Raiz Sem Acesso', 'raizsem');
                } catch (IllegalArgumentException e) {
                    System.debug(LoggingLevel.WARN, 'Usuario sem acesso nao criado: ' + e.getMessage());
                }
            }
        }
    }

    public static final String EMAIL_APROVADOR = 'raiz.aprovador@metodo-raiz.demo';

    /** Usuario com EBL_RAIZ_Cockpit + RAIZ_Aprovador (Onda 5). Chamar no @TestSetup. */
    public static void criarAprovador() {
        List<Id> psIds = new List<Id>();
        for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name IN ('EBL_RAIZ_Cockpit', 'RAIZ_Aprovador')]) {
            psIds.add(ps.Id);
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            List<Id> perfis = new List<Id>{ UserInfo.getProfileId() };
            for (Profile p : [SELECT Id FROM Profile WHERE UserLicense.Name = 'Salesforce Platform' ORDER BY Name LIMIT 3]) {
                perfis.add(p.Id);
            }
            User u = inserirPrimeiro(perfis, EMAIL_APROVADOR, 'Raiz Aprovador', 'raizapr');
            List<PermissionSetAssignment> psa = new List<PermissionSetAssignment>();
            for (Id ps : psIds) {
                psa.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps));
            }
            insert psa;
        }
    }

    public static User usuarioAprovador() {
        return [SELECT Id FROM User WHERE Email = :EMAIL_APROVADOR ORDER BY CreatedDate DESC LIMIT 1];
    }

    private static User inserirPrimeiro(List<Id> perfis, String email, String sobrenome, String alias) {
        String ultimoErro = '';
        for (Id perfilId : perfis) {
            User u = new User(
                Username = String.valueOf(Math.abs(Crypto.getRandomInteger())) + '.' + email,
                LastName = sobrenome,
                Email = email,
                Alias = alias,
                ProfileId = perfilId,
                TimeZoneSidKey = 'America/Sao_Paulo',
                LocaleSidKey = 'pt_BR',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'pt_BR'
            );
            Database.SaveResult sr = Database.insert(u, false);
            if (sr.isSuccess()) {
                return u;
            }
            ultimoErro = sr.getErrors()[0].getMessage();
        }
        throw new IllegalArgumentException('Nao foi possivel criar usuario de teste: ' + ultimoErro);
    }

    public static User usuarioRaiz() {
        return [SELECT Id FROM User WHERE Email = :EMAIL_RAIZ ORDER BY CreatedDate DESC LIMIT 1];
    }

    /** Pode ser nulo se a org nao tiver perfil disponivel. */
    public static User usuarioSemAcesso() {
        List<User> us = [SELECT Id FROM User WHERE Email = :EMAIL_SEM ORDER BY CreatedDate DESC LIMIT 1];
        return us.isEmpty() ? null : us[0];
    }

    public static Account conta(String nome) {
        Account a = new Account(Name = nome);
        insert a;
        return a;
    }

    public static Processo_Critico__c processo(
        Id contaId,
        String nome,
        String criticidade,
        Integer declarado,
        Decimal impactoHora,
        Decimal horas
    ) {
        return new Processo_Critico__c(
            Name = nome,
            Conta__c = contaId,
            Area__c = 'Fiscal',
            Criticidade__c = criticidade,
            Pessoas_Aptas__c = declarado,
            Status_Registro__c = 'Registrado',
            Ultima_Revisao__c = Date.today(),
            Validade_Meses__c = 6,
            Impacto_Hora__c = impactoHora,
            Horas_Para_Restabelecer__c = horas,
            Sistema_Origem__c = 'Planilha',
            Dono__c = UserInfo.getUserId()
        );
    }

    public static Profissional__c profissional(Id contaId, String nome) {
        return new Profissional__c(Name = nome, Conta__c = contaId, Ativo__c = true, Area__c = 'Fiscal');
    }

    public static Habilitacao__c habilitacao(Id processoId, Id profissionalId, String status, Date validaAte) {
        return new Habilitacao__c(
            Processo__c = processoId,
            Profissional__c = profissionalId,
            Status__c = status,
            Valida_Ate__c = validaAte,
            Ultima_Avaliacao__c = Date.today(),
            Evidencia__c = 'Execucao assistida (teste)'
        );
    }
}
