import { defineConfig } from 'vitepress';

// The manual of TuxAide, published on GitHub Pages (hence the base path) by
// .github/workflows/pages.yml when a release is published.
export default defineConfig({
  lang: 'en',
  title: 'TuxAide',
  description: 'Ask your terminal in plain English. A local AI assistant for bash and zsh.',
  base: '/tuxaide/',
  cleanUrls: true,
  lastUpdated: false,
  head: [
    ['meta', { name: 'theme-color', content: '#1e1e2e' }],
    ['link', { rel: 'icon', type: 'image/svg+xml', href: '/tuxaide/logo.svg' }],
    ['meta', { property: 'og:image', content: 'https://deltaxmodules.github.io/tuxaide/video/tuxaide-demo.jpg' }],
  ],
  themeConfig: {
    logo: { src: '/logo.svg', alt: '' },
    siteTitle: 'TuxAide',
    nav: [
      { text: 'Get started', link: '/guide/get-started' },
      { text: 'Commands', link: '/reference/commands' },
      { text: 'Changelog', link: 'https://github.com/deltaxmodules/tuxaide/blob/main/CHANGELOG.md' },
    ],
    sidebar: [
      {
        text: 'Start here',
        items: [
          { text: 'What is TuxAide?', link: '/' },
          { text: 'Install and first question', link: '/guide/get-started' },
          { text: 'How does it know it\'s a question?', link: '/guide/how-it-knows' },
        ],
      },
      {
        text: 'Using it',
        items: [
          { text: 'Answers and your prompt', link: '/guide/answers-and-the-prompt' },
          { text: 'When a command fails', link: '/guide/when-a-command-fails' },
          { text: 'Follow-ups and your system', link: '/guide/follow-ups' },
          { text: 'Smart RAG: your man pages', link: '/guide/smart-rag' },
        ],
      },
      {
        text: 'Models',
        items: [
          { text: 'Models and memory', link: '/guide/models-and-memory' },
          { text: 'Remote backends', link: '/guide/remote-backends' },
        ],
      },
      {
        text: 'Good to know',
        items: [
          { text: 'Privacy: what is kept', link: '/guide/privacy' },
          { text: 'Something not working?', link: '/guide/troubleshooting' },
          { text: 'How it compares', link: '/guide/compare' },
        ],
      },
      {
        text: 'Reference',
        items: [
          { text: 'Commands', link: '/reference/commands' },
          { text: 'Settings', link: '/reference/settings' },
        ],
      },
    ],
    search: { provider: 'local' },
    socialLinks: [{ icon: 'github', link: 'https://github.com/deltaxmodules/tuxaide' }],
    outline: { level: [2, 3], label: 'On this page' },
    footer: { message: 'MIT License', copyright: 'TuxAide by deltaXmodules' },
  },
});
