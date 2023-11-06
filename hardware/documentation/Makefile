all: reDIP-CIA-sch.pdf reDIP-CIA-pcb.pdf reDIP-CIA-BOM.xlsx

reDIP-CIA-sch.pdf: ../reDIP-CIA.kicad_sch
	kicad-cli sch export pdf $< -o $@
reDIP-CIA-pcb.pdf: ../reDIP-CIA.kicad_pcb
	kicad-cli pcb export pdf $< --layers "F.Cu,In1.Cu,In2.Cu,B.Cu,B.Paste,F.Paste,B.SilkS,F.SilkS,B.Mask,F.Mask,Dwgs.User,Edge.Cuts,B.CrtYd,F.CrtYd,B.Fab,F.Fab" -o $@
reDIP-CIA-BOM.xlsx: reDIP-CIA-bom.xml
	kicost -i $< --fields Notes --overwrite -o $@
reDIP-CIA-bom.xml: ../reDIP-CIA.kicad_sch
	kicad-cli sch export python-bom $<

.PHONY: all
