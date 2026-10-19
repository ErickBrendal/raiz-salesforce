import { createElement } from 'lwc';
import Cmp from 'c/raizPortfolioDemo';
import getPainel from '@salesforce/apex/RaizEngineeringService.getPainel';
import { ROTEIRO } from '../roteiro';

jest.mock('@salesforce/apex/RaizEngineeringService.getPainel', () => ({ default: jest.fn() }), { virtual: true });
const flush = () => new Promise((r) => setTimeout(r, 0));
const montar = () => { const el = createElement('c-raiz-portfolio-demo', { is: Cmp }); document.body.appendChild(el); return el; };
const q = (el, s) => el.shadowRoot.querySelector(s);

describe('c-raiz-portfolio-demo', () => {
    afterEach(() => { while (document.body.firstChild) document.body.removeChild(document.body.firstChild); jest.clearAllMocks(); });

    it('roteiro cabe em 7 a 10 minutos e toda etapa tem o que o brief pede', () => {
        const total = ROTEIRO.reduce((s, p) => s + p.minutos, 0);
        expect(total).toBeGreaterThanOrEqual(7);
        expect(total).toBeLessThanOrEqual(10);
        ROTEIRO.forEach((p) => {
            ['funcional', 'tecnico', 'clicar', 'registro', 'esperado', 'comprovar', 'pergunta', 'resposta', 'limitacao'].forEach((k) => {
                expect(p[k]).toBeTruthy();
            });
        });
    });

    it('alterna funcional e tecnico, navega e mostra Engineering with AI com dados da org', async () => {
        getPainel.mockResolvedValue({
            indicadores: [{ chave: 'comp-ver', rotulo: 'Componentes verificados', valor: '50 de 50', regra: 'Verificador.' }],
            funcionalidades: [{ id: 'f1', nome: 'Cadastro guiado', onda: 'Onda 6', portfolio: true, humano: 'Escolheu LWC (D1).', usoIa: 'Código com IA.' }]
        });
        const el = montar();
        await flush();
        expect(el.shadowRoot.querySelectorAll('.lado button').length).toBe(ROTEIRO.length);
        expect(q(el, '[data-id="texto"]').textContent).toBe(ROTEIRO[0].funcional);
        expect(q(el, '[data-id="qa"]')).toBeNull();
        q(el, '[data-id="modo-tecnico"]').click();
        await flush();
        expect(q(el, '[data-id="texto"]').textContent).toBe(ROTEIRO[0].tecnico);
        expect(q(el, '[data-id="qa"]').textContent).toContain(ROTEIRO[0].pergunta);
        q(el, '[data-passo="simulador"]').click();
        await flush();
        expect(q(el, '[data-id="passo"]').textContent).toContain('Fabio Teixeira');
        expect(q(el, '[data-id="ia"]').textContent).toContain('Escolheu LWC (D1).');
        expect(q(el, '[data-id="ia"]').textContent).toContain('50 de 50');
        expect(el.shadowRoot.textContent).toContain('Dados fictícios');
    });
});
