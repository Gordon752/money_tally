const globals = require("globals");

module.exports = [
  {
    files: ["**/*.js"],
    languageOptions: {
      ecmaVersion: 2022,
      globals: globals.node,
      sourceType: "commonjs",
    },
    rules: {
      "no-unused-vars": "error",
      "no-undef": "error",
    },
  },
];
