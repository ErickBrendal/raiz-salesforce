import { createElement } from 'lwc';
import Cmp from 'c/raizEngineeringIntelligence';
import getPainel from '@salesforce/apex/RaizEngineeringService.getPainel';
import verificar from '@salesforce/apex/RaizEngineeringVerifier.verificar';

jest.mock('@salesforce/apex/RaizEngineeringService.getPainel', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RaizEngineeringVerifier.verificar', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RaizGitHubService.getEstado', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/RaizGitHubService.sincronizar', () => ({ default: jest.fn() }), { virtual: true });
import getEstado from '@salesforce/apex/RaizGitHubService.getEstado';
import sincronizar from '@salesforce/apex/RaizGitHubService.sincronizar';

const PAINEL = {
    indicadores: [
        { chave: 'comp-ver', rotulo: 'Componentes verificados', valor: '40 de 44', regra: 'Estado Verificado pelo verificador.', tom: 'atencao' },
        { chave: 'testes', rotulo: 'Testes na última implantação', valor: '77 de 77', regra: 'Do deploy registrado pelo sf CLI.', tom: 'bom' }
    ],
    funcionalidades: [
        { id: 'f1', nome: 'Cadastro guiado', modulo: 'Cadastro guiado', onda: 'Onda 6', status: 'Implementado', estado: 'Verificado', componentes: 3, componentesVerificados: 3, portfolio: true, humano: 'Escolheu LWC (D1).', usoIa: 'Código gerado com IA.', evidenciasAprovadas: 4 },
        { id: 'f2', nome: 'Integração GitHub', modulo: 'Integração', onda: 'Onda 9', status: 'Planejado', estado: 'Declarado', componentes: 0, componentesVerificados: 0, portfolio: false }
    ],
    componentes: [
        { id: 'c1', nome: 'RaizJourneyService', tipo: 'Classe Apex', api: 'RaizJourneyService', modulo: 'Cadastro guiado', estado: 'Verificado', resultado: 'Classe existe.', adr: 'ADR-011' },
        { id: 'c2', nome: 'raizGuidedJourney', tipo: 'LWC', api: 'raizGuidedJourney', modulo: 'Cadastro guiado', estado: 'Nao verificavel', resultado: 'Apex não enxerga LWC.' },
        { id: 'c3', nome: 'Inexistente', tipo: 'Campo', api: 'X__c.Y__c', modulo: 'Plataforma', estado: 'Falhou', resultado: 'Campo não encontrado.' }
    ],
    implantacoes: [],
    logs: [{ nome: 'LOG-00001', tipo: 'Automação', etapa: 'submissao', status: 'Bloqueado', execucoes: 2, quando: '2026-10-18T22:00:00Z', mensagem: 'Bloqueado: falta Revisor.' }],
    pendencias: ['Integração GitHub: planejado.'],
    ultimaVerificacao: '2026-10-18T22:00:00Z',
    origemVerificacao: 'Verificador Apex'
};
const flush = () => new Promise((r) => setTimeout(r, 0));
const montar = () => { const el = createElement('c-raiz-engineering-intelligence', { is: Cmp }); document.body.appendChild(el); return el; };
const q = (el, s) => el.shadowRoot.querySelector(s);
const qa = (el, s) => [...el.shadowRoot.querySelectorAll(s)];
const aba = (el, chave) => q(el, `button[data-chave="${chave}"]`).click();

describe('c-raiz-engineering-intelligence', () => {
    afterEach(() => { while (document.body.firstChild) document.body.removeChild(document.body.firstChild); jest.clearAllMocks(); });

    it('visao executiva mostra cada indicador com a sua regra e a origem da verificacao', async () => {
        getPainel.mockResolvedValue(PAINEL);
        const el = montar();
        await flush();
        expect(qa(el, '.abas button').length).toBe(8);
        const kpi = q(el, '[data-kpi="testes"]');
        expect(kpi.textContent).toContain('77 de 77');
        expect(kpi.textContent).toContain('sf CLI');
        expect(q(el, '[data-id="carimbo"]').textContent).toContain('Verificador Apex');
        expect(el.shadowRoot.textContent).toContain('Integração GitHub: planejado.');
    });

    it('visoes tecnica, portfolio, automacao e implantacoes', async () => {
        getPainel.mockResolvedValue(PAINEL);
        const el = montar();
        await flush();
        aba(el, 'tecnica');
        await flush();
        expect(qa(el, 'tbody tr').length).toBe(3);
        expect(el.shadowRoot.textContent).toContain('Não verificável');
        aba(el, 'portfolio');
        await flush();
        expect(el.shadowRoot.textContent).toContain('Escolheu LWC (D1).');
        expect(el.shadowRoot.textContent).not.toContain('Integração GitHub');
        aba(el, 'automacao');
        await flush();
        expect(q(el, 'tbody .chip_aviso').textContent).toBe('Bloqueado');
        aba(el, 'implantacoes');
        await flush();
        expect(q(el, '[data-id="sem-implantacoes"]')).not.toBeNull();
    });

    it('verificar agora chama o Apex, recarrega e informa o resultado', async () => {
        getPainel.mockResolvedValue(PAINEL);
        verificar.mockResolvedValue({ verificados: 40, falhas: 1, naoVerificaveis: 2, planejados: 3 });
        const el = montar();
        await flush();
        [...el.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === 'Verificar agora').dispatchEvent(new CustomEvent('click'));
        await flush();
        await flush();
        expect(verificar).toHaveBeenCalled();
        expect(getPainel).toHaveBeenCalledTimes(2);
        expect(q(el, '[data-id="aviso"]').textContent).toContain('40 verificados, 1 com falha');
    });

    it('erro de permissao aparece em vez de tela vazia', async () => {
        getPainel.mockResolvedValue({ erro: 'Sem acesso ao inventário de engenharia.', indicadores: [], funcionalidades: [], componentes: [], implantacoes: [], logs: [], pendencias: [] });
        const el = montar();
        await flush();
        expect(el.shadowRoot.textContent).toContain('Sem acesso');
        expect(q(el, '.abas')).toBeNull();
    });
    it('integracao mostra releases, se foram implantadas, e sincroniza sob demanda', async () => {
        getPainel.mockResolvedValue(PAINEL);
        getEstado.mockResolvedValue({
            config: { owner: 'ErickBrendal', repositorio: 'raiz-salesforce', credencial: 'RAIZ_GitHub', demonstracao: false },
            releases: [
                { tag: 'v1.0.0', nome: 'RAIZ 1.0', implantada: true, implantacoes: 1 },
                { tag: 'v1.1.0', nome: 'RAIZ 1.1', implantada: false, implantacoes: 0 }
            ],
            execucoes: [{ status: 'Erro', codigoHttp: 404, mensagem: 'Repositório não encontrado (404).', quando: '2026-10-19T10:00:00Z' }]
        });
        sincronizar.mockResolvedValue({ status: 'Sucesso', mensagem: '2 releases lidas.' });
        const el = montar();
        await flush();
        aba(el, 'integracao');
        await flush();
        await flush();
        expect(q(el, '[data-id="repo"]').textContent).toContain('ErickBrendal/raiz-salesforce');
        const linhas = qa(el, 'tbody tr');
        expect(linhas[0].textContent).toContain('Sim (1)');
        expect(linhas[1].textContent).toContain('Não');
        expect(el.shadowRoot.textContent).toContain('404');
        [...el.shadowRoot.querySelectorAll('lightning-button')].find((b) => b.label === 'Sincronizar agora').dispatchEvent(new CustomEvent('click'));
        await flush();
        await flush();
        expect(sincronizar).toHaveBeenCalled();
        expect(q(el, '[data-id="aviso-integracao"]').textContent).toContain('Sucesso: 2 releases lidas.');
    });
});
