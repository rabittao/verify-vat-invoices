const fs = require('fs');
class RetryPlan {
  constructor(file) {
    this.file = file;
    this.data = JSON.parse(fs.readFileSync(file, 'utf8'));
    if (!Array.isArray(this.data.invoices) || !this.data.invoices.length) throw Error('Empty retry plan');
    this.entries = new Map();
    for (const row of this.data.invoices) {
      if (!/^\d{20}$/.test(row.invoice_number) || !Number.isInteger(row.used_attempts) || row.used_attempts < 0 || row.used_attempts > 3 || this.entries.has(row.invoice_number)) throw Error('Invalid retry budget');
      this.entries.set(row.invoice_number, row);
    }
  }
  includes(number) { return this.entries.has(number); }
  used(number) { return this.entries.get(number).used_attempts; }
  bind(page, number) {
    const entry = this.entries.get(number);
    Object.defineProperty(page, 'invoiceOcrAttempts', { configurable: true,
      get: () => entry.used_attempts,
      set: value => {
        if (!Number.isInteger(value) || value < 0 || value > 3) throw Error('Retry budget exceeded');
        entry.used_attempts = value;
        const temp = this.file + '.tmp';
        fs.writeFileSync(temp, JSON.stringify(this.data, null, 2));
        fs.renameSync(temp, this.file);
      },
    });
  }
}
module.exports = { RetryPlan };
