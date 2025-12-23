import type { ReferenceCardData, ReferenceSection } from '../../common/referenceModels';

export interface SectionWithCards {
  section: ReferenceSection;
  cards: Array<ReferenceCardData>;
}

export interface CardMargin {
  left: number;
  right: number;
  top: number;
  bottom: number;
}

