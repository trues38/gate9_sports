const defaultTheme = require('tailwindcss/defaultTheme')

module.exports = {
  content: [
    './public/*.html',
    './app/helpers/**/*.rb',
    './app/javascript/**/*.js',
    './app/views/**/*.{erb,haml,html,slim}'
  ],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        primary: "#8b5cf6",
        secondary: "#06b6d4",
        terminal: {
          bg: "#010409",
          panel: "rgba(13, 17, 23, 0.7)",
          green: "#00ff41",
          amber: "#ffb000",
          blue: "#00e5ff",
          red: "#ff3131",
          border: "rgba(48, 54, 61, 0.5)",
          text: "#c9d1d9",
          dim: "#8b949e",
        }
      },
      fontFamily: {
        sans: ['"Inter"', ...defaultTheme.fontFamily.sans],
        display: ['"Rajdhani"', 'sans-serif'],
        mono: ['"JetBrains Mono"', 'monospace'],
      },
      fontSize: {
        'xxs': ['0.625rem', { lineHeight: '1rem' }],
        'terminal-sm': ['0.75rem', { lineHeight: '1.1' }],
        'terminal-base': ['0.875rem', { lineHeight: '1.2' }],
      },
      spacing: {
        'grid-gap': '1px',
      }
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('@tailwindcss/typography'),
  ]
}
