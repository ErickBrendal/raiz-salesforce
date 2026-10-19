// RAIZ Onda 6 — usuario ficticio "Revisor Demo" (decisao D4). Idempotente.
// O e-mail e substituido pelo script implantar-onda6.sh (__EMAIL__); o usuario recebe
// o e-mail de boas-vindas da Salesforce para definir a propria senha.
String email = '__EMAIL__';
String usuario = 'revisor.demo.raiz.' + String.valueOf(UserInfo.getOrganizationId()).left(15).toLowerCase() + '@example.com';
List<User> ja = [SELECT Id, IsActive FROM User WHERE Username = :usuario LIMIT 1];
User u;
if (!ja.isEmpty()) {
    u = ja[0];
    System.debug(LoggingLevel.ERROR, 'RAIZ REVISOR: ja existia (ativo=' + u.IsActive + ').');
} else {
    String ultimoErro = '';
    for (Profile p : [SELECT Id, Name FROM Profile WHERE Name IN ('Standard Platform User', 'Standard User') ORDER BY Name]) {
        User novo = new User(
            Username = usuario, FirstName = 'Revisor', LastName = 'Demo (ficticio)', Email = email,
            Alias = 'revdemo', CommunityNickname = 'revisor.demo.raiz', ProfileId = p.Id,
            TimeZoneSidKey = 'America/Sao_Paulo', LocaleSidKey = 'pt_BR', EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'pt_BR'
        );
        Database.DMLOptions o = new Database.DMLOptions();
        o.EmailHeader.triggerUserEmail = true;
        Database.SaveResult sr = Database.insert(novo, o);
        if (sr.isSuccess()) { u = novo; System.debug(LoggingLevel.ERROR, 'RAIZ REVISOR: criado com perfil ' + p.Name + '.'); break; }
        ultimoErro = sr.getErrors()[0].getMessage();
    }
    if (u == null) System.debug(LoggingLevel.ERROR, 'RAIZ REVISOR: NAO criado: ' + ultimoErro);
}
if (u != null) {
    Set<Id> tem = new Set<Id>();
    for (PermissionSetAssignment a : [SELECT PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = :u.Id]) tem.add(a.PermissionSetId);
    List<PermissionSetAssignment> novas = new List<PermissionSetAssignment>();
    for (PermissionSet ps : [SELECT Id, Name FROM PermissionSet WHERE Name IN ('EBL_RAIZ_Cockpit', 'RAIZ_Aprovador')]) {
        if (!tem.contains(ps.Id)) novas.add(new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id));
    }
    insert novas;
    System.debug(LoggingLevel.ERROR, 'RAIZ REVISOR: permission sets atribuidos agora=' + novas.size() + ' usuario=' + usuario);
}
