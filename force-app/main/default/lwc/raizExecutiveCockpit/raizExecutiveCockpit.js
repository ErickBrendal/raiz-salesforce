import { LightningElement, track, wire } from 'lwc';
import getCockpit   from '@salesforce/apex/RaizCockpitService.getCockpit';
import getClientes  from '@salesforce/apex/RaizCockpitService.getClientes';

/**
 * Cockpit Executivo do Metodo RAIZ — EBL Solucoes Corporativas.
 *
 * PRINCIPIO DE CONSTRUCAO
 * Todo numero exibido aqui e calculado no Apex a partir de registro real.
 * O componente nao inventa media, nao estima e nao preenche lacuna com zero
 * disfarcado de "tudo certo". Quando nao ha dado, ele diz que nao ha dado —
 * porque painel que mostra verde por falta de informacao e pior que painel
 * nenhum: ele produz confianca sem base.
 */
const CLASSE_ESTADO = {
    'Sem cobertura': 'est_sem',
    'Ponto unico': 'est_ponto',
    'Informacao insuficiente': 'est_insuf',
    'Coberto': 'est_cob'
};
const CHIP_ESTADO = {
    'Sem cobertura': ['chip-est chip-est_sem', 'Sem cobertura'],
    'Ponto unico': ['chip-est chip-est_ponto', 'Ponto único'],
    'Informacao insuficiente': ['chip-est', 'Sem informação'],
    'Coberto': ['chip-est chip-est_cob', 'Coberto']
};

export default class RaizExecutiveCockpit extends LightningElement {

    @track dados = null;
    @track clientes = [];

    contaId   = '';
    carregando = true;
    erro = null;

    // ---------------------------------------------------------------- wires
    @wire(getClientes)
    wiredClientes({ data, error }) {
        if (data) this.clientes = data;
        if (error) this.erro = this.msg(error);
    }

    @wire(getCockpit, { contaId: '$contaIdParam' })
    wiredCockpit({ data, error }) {
        this.carregando = false;
        if (data) {
            this.dados = data;
            this.erro = null;
        }
        if (error) {
            this.dados = null;
            this.erro = this.msg(error);
        }
    }

    get contaIdParam()   { return this.contaId   ? this.contaId   : null; }

    msg(e) {
        if (!e) return 'Erro desconhecido.';
        if (e.body && e.body.message) return e.body.message;
        if (e.message) return e.message;
        return JSON.stringify(e);
    }

    // ------------------------------------------------------------- estados
    get pronto()        { return !this.carregando && !this.erro && !!this.dados && !this.dados.semPermissao; }
    get temRessalvas()  { return this.dados && this.dados.ressalvas && this.dados.ressalvas.length > 0; }
    get semPermissao()  { return !!(this.dados && this.dados.semPermissao); }

    get estados() {
        if (!this.dados || !this.dados.estadosCobertura) return [];
        return this.dados.estadosCobertura.map(e => ({ ...e, classe: 'est ' + (CLASSE_ESTADO[e.rotulo] || '') }));
    }
    get reducaoTexto() {
        if (!this.dados || !this.dados.processosComPlano) return '—';
        return this.dados.scoreInicialPlanos + ' → ' + this.dados.scoreAtualPlanos;
    }
    get classeGovAtrasadas() {
        return 'mit-num' + (this.dados && this.dados.govAtrasadas > 0 ? ' mit-num_alerta' : '');
    }
    get classeGovBloqueadas() {
        return 'mit-num' + (this.dados && this.dados.govBloqueadas > 0 ? ' mit-num_alerta' : '');
    }

    get classeAtrasados() {
        return 'mit-num' + (this.dados && this.dados.planosAtrasados > 0 ? ' mit-num_alerta' : '');
    }

    get textoBase() {
        const n = this.dados ? this.dados.totalProcessos : 0;
        return n === 1 ? '1 processo inventariado' : n + ' processos inventariados';
    }
    get temPessoas()    { return this.dados && this.dados.pessoasChave && this.dados.pessoasChave.length > 0; }

    // ------------------------------------------------------------- eventos
    mudarCliente(e) {
        this.contaId = e.detail.value;
        this.carregando = true;
    }

    // ------------------------------------------------------ transformacoes
    // O LWC PROIBE usar o indice do for:each como key — o indice muda quando a
    // lista e reordenada, e o framework perde o rastro do elemento. Como as
    // ressalvas sao strings soltas, viram objetos com id proprio aqui.
    get ressalvas() {
        if (!this.dados || !this.dados.ressalvas) return [];
        return this.dados.ressalvas.map((t, i) => ({ id: 'rs' + i + '-' + t.length, texto: t }));
    }

    // Classe CSS por tom vem do Apex, nao de logica duplicada no JS.
    get indicadoresComClasse() {
        if (!this.dados) return [];
        return this.dados.indicadores.map(i => ({ ...i, classe: 'kpi kpi_' + i.tom }));
    }

    get pessoasComBarra() {
        if (!this.dados || !this.dados.pessoasChave.length) return [];
        const max = Math.max(...this.dados.pessoasChave.map(p => p.processosSozinho), 1);
        return this.dados.pessoasChave.map(p => ({
            ...p,
            estilo: `width:${Math.round((p.processosSozinho / max) * 100)}%`
        }));
    }

    get ondeViveComBarra() {
        if (!this.dados) return [];
        return this.dados.ondeVive.map(o => ({
            ...o,
            estilo: `width:${o.percentual}%`,
            // "So na cabeca da pessoa" e o oposto do que o metodo entrega.
            // Ele aparece em vermelho para nao passar como mais uma categoria.
            classe: (o.rotulo === 'So na cabeca da pessoa' || o.rotulo === 'Papel')
                ? 'barra-preenche barra-preenche_ruim'
                : (o.rotulo === 'Salesforce' || o.rotulo === 'ERP')
                    ? 'barra-preenche barra-preenche_bom'
                    : 'barra-preenche'
        }));
    }

    get matrizComBarra() {
        if (!this.dados) return [];
        const max = Math.max(...this.dados.matrizRisco.map(m => m.quantidade), 1);
        const mapa = {
            'Critico': ['farol-num farol-num_critico', 'farol-barra farol-barra_critico'],
            'Alto':    ['farol-num farol-num_alto',    'farol-barra farol-barra_alto'],
            'Medio':   ['farol-num farol-num_medio',   'farol-barra farol-barra_medio'],
            'Baixo':   ['farol-num farol-num_baixo',   'farol-barra farol-barra_baixo']
        };
        const ordem = ['Critico', 'Alto', 'Medio', 'Baixo'];
        return [...this.dados.matrizRisco]
            .sort((a, b) => ordem.indexOf(a.rotulo) - ordem.indexOf(b.rotulo))
            .map(m => {
                const c = mapa[m.rotulo] || ['farol-num', 'farol-barra'];
                return {
                    ...m,
                    classeNum: c[0],
                    classeBarra: c[1],
                    estilo: `width:${Math.round((m.quantidade / max) * 100)}%`
                };
            });
    }

    get topComEstilo() {
        if (!this.dados) return [];
        return this.dados.topRiscos.map(t => ({
            ...t,
            pontoClasse: t.pontoUnico ? 'ponto ponto_alerta' : 'ponto',
            estadoClasse: (CHIP_ESTADO[t.estadoCobertura] || ['chip-est'])[0],
            estadoRotulo: (CHIP_ESTADO[t.estadoCobertura] || ['', t.estadoCobertura])[1],
            sistemaIcone: t.aplicadoNoSistema ? '✓' : '—',
            scoreClasse: t.score >= 16 ? 'score score_critico'
                       : t.score >= 9  ? 'score score_alto'
                       : t.score >= 5  ? 'score score_medio'
                                       : 'score score_baixo'
        }));
    }

    // O template itera sobre esta versao, nao sobre dados.indicadores cru,
    // para que a classe de tom exista de verdade no objeto renderizado.
    // (Um .map() que descarta o campo usado depois ja nos custou um deploy.)
    get indicadores() { return this.indicadoresComClasse; }
}