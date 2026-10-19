import { createElement } from 'lwc';
import RaizExecutiveCockpit from 'c/raizExecutiveCockpit';
import getCockpit from '@salesforce/apex/RaizCockpitService.getCockpit';
import getClientes from '@salesforce/apex/RaizCockpitService.getClientes';

jest.mock('@salesforce/apex/RaizCockpitService.getCockpit', () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
}, { virtual: true });
jest.mock('@salesforce/apex/RaizCockpitService.getClientes', () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
}, { virtual: true });

const DADOS = {
    cliente: 'Todos os clientes', totalProcessos: 1, geradoEm: '17/10/2026 18:00',
    indicadores: [{ chave: 'exposicao', rotulo: 'Exposição financeira', valor: 2095400, valorFormatado: 'R$ 2.095.400', unidade: 'em risco', explicacao: 'x', tom: 'critico' }],
    ressalvas: ['1 processo sem dono definido.'],
    pessoasChave: [{ userId: 'pr1', nome: 'Fabio Teixeira', processosSozinho: 3, exposicaoFmt: 'R$ 620.000' }],
    ondeVive: [{ rotulo: 'So na cabeca da pessoa', rotuloExibicao: 'Só na cabeça da pessoa', quantidade: 1, percentual: 100 }],
    matrizRisco: [{ rotulo: 'Medio', rotuloExibicao: 'Médio', quantidade: 1 }, { rotulo: 'Critico', rotuloExibicao: 'Crítico', quantidade: 2 }],
    estadosCobertura: [{ rotulo: 'Sem cobertura', rotuloExibicao: 'Sem cobertura', quantidade: 2, percentual: 10 },
        { rotulo: 'Ponto unico', rotuloExibicao: 'Ponto único', quantidade: 10, percentual: 50 },
        { rotulo: 'Informacao insuficiente', rotuloExibicao: 'Informação insuficiente', quantidade: 0, percentual: 0 },
        { rotulo: 'Coberto', rotuloExibicao: 'Coberto', quantidade: 8, percentual: 40 }],
    coberturaEvidenciada: 20, coberturaDeclarada: 0, informacaoInsuficiente: 0,
    planosAbertos: 3, planosAtrasados: 1, processosComPlano: 3, scoreInicialPlanos: 72, scoreAtualPlanos: 54, pontosUnicosSemPlano: 9,
    topRiscos: [{ id: 't1', estadoCobertura: 'Ponto unico', fonteCobertura: 'Habilitacoes', processo: 'Roteiro', areaRotulo: 'Produção', dono: 'Erick', aptosTexto: '—', pontoUnico: false, aplicadoNoSistema: false, score: 12, exposicaoFmt: 'R$ 0' }]
};
const flush = () => Promise.resolve().then(() => Promise.resolve());

describe('c-raiz-executive-cockpit', () => {
    afterEach(() => { while (document.body.firstChild) document.body.removeChild(document.body.firstChild); });

    it('mostra rotulos com acento, sem o simulador antigo', async () => {
        const el = createElement('c-raiz-executive-cockpit', { is: RaizExecutiveCockpit });
        document.body.appendChild(el);
        getClientes.emit([{ label: 'Todos os clientes', value: '' }]);
        getCockpit.emit(DADOS);
        await flush();
        const txt = el.shadowRoot.textContent;
        expect(txt).toContain('R$ 2.095.400');
        expect(txt).toContain('Só na cabeça da pessoa');
        expect(txt).toContain('Crítico');
        expect(txt).toContain('Produção');
        expect(txt).toContain('Fabio Teixeira');
        expect(txt).toContain('1 processo inventariado');
        expect(txt).not.toContain('Se essa pessoa sair amanhã');
        expect(el.shadowRoot.querySelector('[data-id="reducao"]').textContent).toBe('72 → 54');
        expect(el.shadowRoot.querySelector('[data-id="atrasados"]').className).toContain('mit-num_alerta');
        expect(el.shadowRoot.querySelectorAll('.est').length).toBe(4);
        expect(el.shadowRoot.querySelector('.est_ponto').textContent).toContain('Ponto único');
        expect(el.shadowRoot.querySelector('.chip-est_ponto').textContent).toBe('Ponto único');
        expect(el.shadowRoot.querySelector('[data-id="sem-permissao"]')).toBeNull();
        const farois = el.shadowRoot.querySelectorAll('.farol-rot');
        expect(farois[0].textContent).toBe('Crítico');
    });

    it('erro aparece e troca de cliente recarrega', async () => {
        const el = createElement('c-raiz-executive-cockpit', { is: RaizExecutiveCockpit });
        document.body.appendChild(el);
        getCockpit.error({ message: 'falhou' });
        await flush();
        expect(el.shadowRoot.textContent).toContain('falhou');
        el.shadowRoot.querySelector('lightning-combobox').dispatchEvent(new CustomEvent('change', { detail: { value: 'c1' } }));
        await flush();
        expect(getCockpit.getLastConfig()).toEqual({ contaId: 'c1' });
    });

    it('sem permissao avisa e nao mostra reducao inventada', async () => {
        const el = createElement('c-raiz-executive-cockpit', { is: RaizExecutiveCockpit });
        document.body.appendChild(el);
        getCockpit.emit({ ...DADOS, semPermissao: true, processosComPlano: 0, planosAtrasados: 0 });
        await flush();
        expect(el.shadowRoot.querySelector('[data-id="sem-permissao"]')).not.toBeNull();
        expect(el.shadowRoot.querySelector('[data-id="reducao"]')).toBeNull();
        expect(el.shadowRoot.textContent).not.toContain('R$ 2.095.400');
    });
    it('governanca documental mostra revisao, atraso e bloqueio (Onda 7)', async () => {
        const cmp = require('lwc').createElement('c-raiz-executive-cockpit', { is: require('c/raizExecutiveCockpit').default });
        document.body.appendChild(cmp);
        getClientes.emit([{ label: 'Todos os clientes', value: '' }]);
        getCockpit.emit({ ...DADOS, govEmRevisao: 3, govAtrasadas: 1, govBloqueadas: 1, govSemPrazo: 2 });
        await Promise.resolve();
        await Promise.resolve();
        const q = (s) => cmp.shadowRoot.querySelector(s);
        expect(q('[data-id="gov-revisao"]').textContent).toBe('3');
        expect(q('[data-id="gov-atrasadas"]').className).toContain('mit-num_alerta');
        expect(q('[data-id="gov-bloqueadas"]').textContent).toBe('1');
        expect(q('[data-id="gov-sem-prazo"]').textContent).toBe('2');
    });
});
