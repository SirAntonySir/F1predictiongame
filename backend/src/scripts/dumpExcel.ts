/**
 * Dump a region of the Excel file to confirm what's where.
 * Usage: npx tsx src/scripts/dumpExcel.ts "<path>" <row> <col> <rows> <cols>
 */
import xlsxPkg from 'xlsx'
const XLSX = xlsxPkg as typeof xlsxPkg & { readFile: (p: string) => xlsxPkg.WorkBook }

const [,, xlsxPath, rowStr, colStr, rowsStr, colsStr] = process.argv
if (!xlsxPath) { console.error('need xlsx path + rect'); process.exit(2) }

const startRow = parseInt(rowStr ?? '70', 10)
const startCol = parseInt(colStr ?? '1', 10)
const nRows = parseInt(rowsStr ?? '10', 10)
const nCols = parseInt(colsStr ?? '15', 10)

const wb = XLSX.readFile(xlsxPath)
const ws = wb.Sheets['Tippspiel 2026']
if (!ws) { console.error('sheet not found'); process.exit(2) }

const header = ['row\\col', ...Array.from({ length: nCols }, (_, i) => `c${startCol + i}`)].join('\t')
console.log(header)
for (let r = startRow; r < startRow + nRows; r++) {
  const cells: string[] = [`r${r}`]
  for (let c = startCol; c < startCol + nCols; c++) {
    const ref = XLSX.utils.encode_cell({ r: r - 1, c: c - 1 })
    const cell = (ws as any)[ref]
    cells.push(cell && cell.v !== null && cell.v !== undefined ? String(cell.v) : '·')
  }
  console.log(cells.join('\t'))
}
