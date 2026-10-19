import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getPainel from '@salesforce/apex/RaizEngineeringService.getPainel';
import { ROTEIRO } from './roteiro';

/**
 * RAIZ Portfolio Demo Mode (Onda 10): roteiro de 7 a 10 minutos com visão
 * funcional e técnica, links para as telas e a seção Engineering with AI
 * alimentada pelo inventário de engenharia (dados reais da org).
 */
export default class RaizPortfolioDemo extends NavigationMixin(LightningElement) {
    modo = 'funcional';
    atual = 0;
    painel;
    erroPainel;

    connectedCallback() {
        getPainel()
            .then((p) => {
                this.painel = p;
                this.erroPainel = p.erro;
            })
            .catch(() => {
                this.erroPainel = 'Inventário de engenharia indisponível.';
            });
    }

    get passos() {
        return ROTEIRO.map((p, i) => ({ ...p, i, n: i + 1, cls: 'passo' + (i === this.atual ? ' passo_atual' : '') }));
    }
    get passo() {
        return this.passos[this.atual];
    }
    get totalMinutos() {
        return ROTEIRO.reduce((s, p) => s + p.minutos, 0).toString().replace('.', ',');
    }
    get tecnico() {
        return this.modo === 'tecnico';
    }
    get texto() {
        return this.tecnico ? this.passo.tecnico : this.passo.funcional;
    }
    get clsFuncional() {
        return 'modo' + (this.modo === 'funcional' ? ' modo_ativo' : '');
    }
    get clsTecnico() {
        return 'modo' + (this.modo === 'tecnico' ? ' modo_ativo' : '');
    }
    get temAba() {
        return !!this.passo.aba;
    }
    get primeiro() {
        return this.atual === 0;
    }
    get ultimo() {
        return this.atual === ROTEIRO.length - 1;
    }
    verFuncional() {
        this.modo = 'funcional';
    }
    verTecnico() {
        this.modo = 'tecnico';
    }
    escolher(e) {
        this.atual = Number(e.currentTarget.dataset.i);
    }
    anterior() {
        if (this.atual > 0) this.atual--;
    }
    proximo() {
        if (this.atual < ROTEIRO.length - 1) this.atual++;
    }
    abrir() {
        this[NavigationMixin.Navigate]({ type: 'standard__navItemPage', attributes: { apiName: this.passo.aba } });
    }

    get destaques() {
        return (this.painel ? this.painel.funcionalidades : []).filter((f) => f.portfolio);
    }
    get indicadores() {
        return (this.painel ? this.painel.indicadores : []).filter((i) => ['func-val', 'comp-ver', 'testes'].includes(i.chave));
    }
}
