import type { ReferenceDoc } from '../../common/referenceModels';
import type { AppThemeTokens } from '../../common/appTheme';
import type { QuizQuestion, QuizAnswer, QuizSession, QuizRecord, QuizOption } from '../../common/quizModels';
import { QuizRepository } from '../../common/quizRepository';
import { formatDuration, formatDateTime } from './utils';
import { calculateScore } from '../../common/quizUtils';

@Component
export struct QuizTab {
  @Prop theme: AppThemeTokens;
  @Prop fontSize: number;
  @Prop lang: 'zh' | 'en';
  @Prop isLandscape: boolean;

  @Link quizMode: 'idle' | 'selecting' | 'answering' | 'result';
  @Link quizQuestions: Array<QuizQuestion>;
  @Link quizCurrentIndex: number;
  @Link quizAnswers: Array<QuizAnswer>;
  @Link quizSelectedOptionIndex: number;
  @Link quizShowAnswer: boolean;
  @Link quizStartTime: number;
  @Link quizQuestionStartTime: number;
  @Link quizRecord: QuizRecord | null;
  @Link quizAvailableCount: number;
  @Link historyListScrollIndex: number;
  @Link answeringScrollY: number;
  @Link resultListScrollIndex: number;

  @Prop selectedDoc: ReferenceDoc | null = null;
  quizRepository: QuizRepository = new QuizRepository();
  historyListScroller: ListScroller = new ListScroller();
  resultListScroller: ListScroller = new ListScroller();
  answeringScroller: Scroller = new Scroller();

  onStartQuiz?: (count: number) => void;
  onSelectQuizOption?: (index: number) => void;
  onConfirmQuizAnswer?: () => void;
  onNextQuizQuestion?: () => void;
  onResetQuiz?: () => void;
  onLandscapeScrollDirection?: (direction: 'up' | 'down') => void;

  private t(zh: string, en: string): string {
    return this.lang === 'en' ? en : zh;
  }

  private getQuizCorrectCount(): number {
    let count = 0;
    for (let i = 0; i < this.quizAnswers.length; i++) {
      if (this.quizAnswers[i].isCorrect) count++;
    }
    return count;
  }

  private getQuizScore(): number {
    return calculateScore(this.getQuizCorrectCount(), this.quizQuestions.length);
  }

  private getOptionLabelColor(optionIndex: number): number {
    if (!this.quizShowAnswer) {
      return optionIndex === this.quizSelectedOptionIndex ? this.theme.accentColor : this.theme.mutedTextColor;
    }
    const option = this.quizQuestions[this.quizCurrentIndex]?.options[optionIndex];
    if (option?.isCorrect) return 0xff4caf50;
    if (optionIndex === this.quizSelectedOptionIndex) return this.theme.dangerTextColor;
    return this.theme.mutedTextColor;
  }

  private getOptionTextColor(optionIndex: number): number {
    if (!this.quizShowAnswer) {
      return optionIndex === this.quizSelectedOptionIndex ? this.theme.titleColor : this.theme.textColor;
    }
    const option = this.quizQuestions[this.quizCurrentIndex]?.options[optionIndex];
    if (option?.isCorrect) return 0xff4caf50;
    if (optionIndex === this.quizSelectedOptionIndex) return this.theme.dangerTextColor;
    return this.theme.textColor;
  }

  private getOptionBackgroundColor(optionIndex: number): number {
    if (!this.quizShowAnswer) {
      return optionIndex === this.quizSelectedOptionIndex ? this.theme.chipSelectedBackgroundColor : this.theme.surfaceBackgroundColor;
    }
    const option = this.quizQuestions[this.quizCurrentIndex]?.options[optionIndex];
    if (option?.isCorrect) return 0x204caf50;
    if (optionIndex === this.quizSelectedOptionIndex && !option?.isCorrect) return 0x20f44336;
    return this.theme.surfaceBackgroundColor;
  }

  private getOptionBorderColor(optionIndex: number): number {
    if (!this.quizShowAnswer) {
      return optionIndex === this.quizSelectedOptionIndex ? this.theme.accentColor : this.theme.borderColor;
    }
    const option = this.quizQuestions[this.quizCurrentIndex]?.options[optionIndex];
    if (option?.isCorrect) return 0xff4caf50;
    if (optionIndex === this.quizSelectedOptionIndex && !option?.isCorrect) return this.theme.dangerTextColor;
    return this.theme.borderColor;
  }

  @Builder
  private QuizIdleView(): void {
    Column({ space: this.fontSize * 0.8 }) {
      if (!this.selectedDoc) {
        Column({ space: this.fontSize * 0.5 }) {
          Text(this.t('请先选择文档', 'Please select a document first'))
            .fontSize(this.fontSize)
            .fontColor(this.theme.mutedTextColor);
          Text(this.t('在"目录"中打开一个文档后，即可开始测验', 'Open a document in "Catalog" to start quiz'))
            .fontSize(this.fontSize * 0.8)
            .fontColor(this.theme.mutedTextColor)
            .opacity(0.7);
        }
        .padding(this.fontSize * 1);
      } else {
        Column({ space: this.fontSize * 0.6 }) {
          Row({ space: this.fontSize * 0.5 }) {
            Text(this.t('当前文档：', 'Current Doc: '))
              .fontSize(this.fontSize)
              .fontColor(this.theme.mutedTextColor);
            Text(this.selectedDoc.name || this.selectedDoc.title)
              .fontSize(this.fontSize)
              .fontColor(this.theme.titleColor)
              .fontWeight(FontWeight.Medium);
          }
          .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });

          Text(this.t(`可生成 ${this.quizAvailableCount} 道题目`, `${this.quizAvailableCount} questions available`))
            .fontSize(this.fontSize * 0.85)
            .fontColor(this.theme.mutedTextColor)
            .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });

          if (this.quizAvailableCount > 0) {
            Row({ space: this.fontSize * 0.6 }) {
              ForEach([5, 10, 15], (count: number) => {
                if (this.quizAvailableCount >= count || count === 5) {
                  Text(this.t(`${Math.min(count, this.quizAvailableCount)} 题`, `${Math.min(count, this.quizAvailableCount)} Q`))
                    .fontSize(this.fontSize * 0.9)
                    .fontColor(this.theme.accentColor)
                    .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 0.6, bottom: this.fontSize * 0.6 })
                    .backgroundColor(this.theme.surfaceBackgroundColor)
                    .border({ width: 1, color: this.theme.accentColor })
                    .borderRadius(this.fontSize * 0.5)
                    .onClick(() => this.onStartQuiz?.(Math.min(count, this.quizAvailableCount)));
                }
              }, (count: number) => `quiz_start_${count}`);
            }
            .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 0.5 });
          } else {
            Text(this.t('当前文档没有可生成测验的表格内容', 'No table content available for quiz in this document'))
              .fontSize(this.fontSize * 0.85)
              .fontColor(this.theme.dangerTextColor)
              .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });
          }
        }
        .width('100%')
        .padding({ top: this.fontSize * 0.5, bottom: this.fontSize * 0.5 })
        .backgroundColor(this.theme.surfaceBackgroundColor)
        .borderRadius(this.fontSize * 0.5)
        .margin({ left: this.fontSize * 1, right: this.fontSize * 1 });
      }

      if (this.quizRecord && this.quizRecord.totalQuizCount > 0) {
        if (!this.isLandscape) {
          Column({ space: this.fontSize * 0.5 }) {
            Text(this.t('测验记录', 'Quiz History'))
              .fontSize(this.fontSize)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.theme.titleColor);

            Row({ space: this.fontSize * 1 }) {
              Column({ space: this.fontSize * 0.2 }) {
                Text(`${this.quizRecord.totalQuizCount}`)
                  .fontSize(this.fontSize * 1.5)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme.accentColor);
                Text(this.t('总测验', 'Total'))
                  .fontSize(this.fontSize * 0.75)
                  .fontColor(this.theme.mutedTextColor);
              }

              Column({ space: this.fontSize * 0.2 }) {
                Text(`${this.quizRecord.averageScore}%`)
                  .fontSize(this.fontSize * 1.5)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme.accentColor);
                Text(this.t('平均分', 'Average'))
                  .fontSize(this.fontSize * 0.75)
                  .fontColor(this.theme.mutedTextColor);
              }

              Column({ space: this.fontSize * 0.2 }) {
                Text(`${this.quizRecord.totalCorrectCount}/${this.quizRecord.totalQuestionCount}`)
                  .fontSize(this.fontSize * 1.5)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.theme.accentColor);
                Text(this.t('正确率', 'Correct'))
                  .fontSize(this.fontSize * 0.75)
                  .fontColor(this.theme.mutedTextColor);
              }
            }
            .justifyContent(FlexAlign.SpaceAround)
            .width('100%');
          }
          .width('100%')
          .padding(this.fontSize * 1)
          .backgroundColor(this.theme.surfaceBackgroundColor)
          .borderRadius(this.fontSize * 0.5)
          .margin({ left: this.fontSize * 1, right: this.fontSize * 1 });
        }

        if (this.quizRecord.sessions.length > 0) {
          Column({ space: this.fontSize * 0.3 }) {
            Text(this.t('最近测验', 'Recent Quizzes'))
              .fontSize(this.fontSize * 0.9)
              .fontColor(this.theme.mutedTextColor)
              .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });

            List({ scroller: this.historyListScroller, initialIndex: this.historyListScrollIndex }) {
              ForEach(this.quizRepository.getRecentSessions(this.quizRecord, 10), (session: QuizSession) => {
                ListItem() {
                  Row() {
                    Column({ space: this.fontSize * 0.15 }) {
                      Text(session.docName || session.docTitle)
                        .fontSize(this.fontSize * 0.9)
                        .fontColor(this.theme.titleColor)
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis });
                      Text(formatDateTime(session.endTime))
                        .fontSize(this.fontSize * 0.75)
                        .fontColor(this.theme.mutedTextColor);
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start);

                    Column({ space: this.fontSize * 0.1 }) {
                      Text(`${session.score}%`)
                        .fontSize(this.fontSize)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(session.score >= 60 ? this.theme.accentColor : this.theme.dangerTextColor);
                      Text(`${session.correctCount}/${session.totalCount}`)
                        .fontSize(this.fontSize * 0.75)
                        .fontColor(this.theme.mutedTextColor);
                    }
                    .alignItems(HorizontalAlign.End);
                  }
                  .width('100%')
                  .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 0.5, bottom: this.fontSize * 0.5 });
                }
              }, (session: QuizSession) => session.id);
            }
            .layoutWeight(1)
            .divider({ strokeWidth: 1, color: this.theme.borderColor, startMargin: this.fontSize * 1, endMargin: this.fontSize * 1 })
            .onScrollIndex((start: number, _end: number) => {
              const previous: number = this.historyListScrollIndex;
              if (previous !== start) {
                if (this.isLandscape) {
                  this.onLandscapeScrollDirection?.(start > previous ? 'up' : 'down');
                }
                this.historyListScrollIndex = start;
              }
            });
          }
          .layoutWeight(1);
        }
      }
    }
    .layoutWeight(1);
  }

  @Builder
  private QuizSelectingView(): void {
    Column({ space: this.fontSize * 0.8 }) {
      Text(this.t('选择题目数量', 'Select Question Count'))
        .fontSize(this.fontSize)
        .fontColor(this.theme.titleColor);
    }
    .padding(this.fontSize * 1);
  }

  @Builder
  private QuizAnsweringView(): void {
    Column({ space: this.fontSize * 0.6 }) {
      Row() {
        Text(`${this.quizCurrentIndex + 1} / ${this.quizQuestions.length}`)
          .fontSize(this.fontSize * 0.9)
          .fontColor(this.theme.mutedTextColor);
        Blank();
        Text(this.t('退出', 'Exit'))
          .fontSize(this.fontSize * 0.9)
          .fontColor(this.theme.dangerTextColor)
          .onClick(() => this.onResetQuiz?.());
      }
      .width('100%')
      .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });

      Progress({ value: this.quizCurrentIndex + 1, total: this.quizQuestions.length })
        .width('100%')
        .color(this.theme.accentColor)
        .backgroundColor(this.theme.surfaceMutedBackgroundColor)
        .margin({ left: this.fontSize * 1, right: this.fontSize * 1 });

      Scroll(this.answeringScroller) {
        Column({ space: this.fontSize * 0.8 }) {
          Text(this.quizQuestions[this.quizCurrentIndex]?.question ?? '')
            .fontSize(this.fontSize * 1.1)
            .fontColor(this.theme.titleColor)
            .fontWeight(FontWeight.Medium)
            .width('100%')
            .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });

          Column({ space: this.fontSize * 0.5 }) {
            ForEach(this.quizQuestions[this.quizCurrentIndex]?.options ?? [], (option: QuizOption, optionIndex: number) => {
              Row({ space: this.fontSize * 0.6 }) {
                Text(String.fromCharCode(65 + optionIndex))
                  .fontSize(this.fontSize)
                  .fontWeight(FontWeight.Bold)
                  .fontColor(this.getOptionLabelColor(optionIndex));

                Text(option.text)
                  .fontSize(this.fontSize)
                  .fontColor(this.getOptionTextColor(optionIndex))
                  .layoutWeight(1);

                if (this.quizShowAnswer) {
                  if (option.isCorrect) {
                    Text('✓')
                      .fontSize(this.fontSize)
                      .fontColor(0xff4caf50);
                  } else if (optionIndex === this.quizSelectedOptionIndex && !option.isCorrect) {
                    Text('✗')
                      .fontSize(this.fontSize)
                      .fontColor(this.theme.dangerTextColor);
                  }
                }
              }
              .width('100%')
              .padding(this.fontSize * 0.8)
              .backgroundColor(this.getOptionBackgroundColor(optionIndex))
              .border({ width: this.fontSize * 0.1, color: this.getOptionBorderColor(optionIndex) })
              .borderRadius(this.fontSize * 0.5)
              .onClick(() => this.onSelectQuizOption?.(optionIndex));
            }, (_option: QuizOption, optionIndex: number) => {
              const qid = this.quizQuestions[this.quizCurrentIndex]?.id ?? 'q';
              return `${qid}_option_${optionIndex}`;
            });
          }
          .width('100%')
          .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });

          if (this.quizShowAnswer && this.quizQuestions[this.quizCurrentIndex]?.explanation) {
            Text(this.quizQuestions[this.quizCurrentIndex].explanation)
              .fontSize(this.fontSize * 0.9)
              .fontColor(this.theme.mutedTextColor)
              .fontStyle(FontStyle.Italic)
              .width('100%')
              .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });
          }
        }
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .onDidScroll((_xOffset: number, _yOffset: number, scrollState: ScrollState) => {
        const yOffset: number = this.answeringScroller.currentOffset().yOffset;
        const previous: number = this.answeringScrollY;
        const delta: number = yOffset - previous;
        const threshold: number = this.fontSize * 0.6;
        if (this.isLandscape && scrollState !== ScrollState.Idle && Math.abs(delta) >= threshold) {
          this.onLandscapeScrollDirection?.(delta > 0 ? 'up' : 'down');
        }
        if (previous !== yOffset) {
          this.answeringScrollY = yOffset;
        }
      })
      .onAppear(() => {
        const yOffset: number = this.answeringScrollY;
        this.answeringScroller.scrollTo({ xOffset: 0, yOffset, animation: false });
      });

      Row({ space: this.fontSize * 1 }) {
        if (!this.quizShowAnswer) {
          Text(this.t('确认答案', 'Confirm'))
            .fontSize(this.fontSize)
            .fontColor(this.quizSelectedOptionIndex >= 0 ? 0xffffffff : this.theme.mutedTextColor)
            .padding({ left: this.fontSize * 1.5, right: this.fontSize * 1.5, top: this.fontSize * 0.8, bottom: this.fontSize * 0.8 })
            .backgroundColor(this.quizSelectedOptionIndex >= 0 ? this.theme.accentColor : this.theme.surfaceMutedBackgroundColor)
            .borderRadius(this.fontSize * 0.5)
            .onClick(() => this.onConfirmQuizAnswer?.());
        } else {
          Text(this.quizCurrentIndex + 1 >= this.quizQuestions.length ? this.t('查看结果', 'View Results') : this.t('下一题', 'Next'))
            .fontSize(this.fontSize)
            .fontColor(0xffffffff)
            .padding({ left: this.fontSize * 1.5, right: this.fontSize * 1.5, top: this.fontSize * 0.8, bottom: this.fontSize * 0.8 })
            .backgroundColor(this.theme.accentColor)
            .borderRadius(this.fontSize * 0.5)
            .onClick(() => this.onNextQuizQuestion?.());
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: this.fontSize * 1, right: this.fontSize * 1, bottom: this.fontSize * 1 });
    }
    .layoutWeight(1)
    .width('100%');
  }

  @Builder
  private QuizResultView(): void {
    Column({ space: this.fontSize * 0.8 }) {
      Column({ space: this.fontSize * 0.3 }) {
        Text(this.t('测验完成！', 'Quiz Complete!'))
          .fontSize(this.fontSize * 1.2)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.theme.titleColor);

        Text(`${this.getQuizScore()}%`)
          .fontSize(this.fontSize * 3)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.getQuizScore() >= 60 ? this.theme.accentColor : this.theme.dangerTextColor);

        Text(this.t(`${this.getQuizCorrectCount()} / ${this.quizQuestions.length} 正确`, `${this.getQuizCorrectCount()} / ${this.quizQuestions.length} Correct`))
          .fontSize(this.fontSize)
          .fontColor(this.theme.mutedTextColor);

        Text(this.t(`用时：${formatDuration(Date.now() - this.quizStartTime)}`, `Duration: ${formatDuration(Date.now() - this.quizStartTime)}`))
          .fontSize(this.fontSize * 0.9)
          .fontColor(this.theme.mutedTextColor);
      }
      .width('100%')
      .padding(this.fontSize * 1.5)
      .backgroundColor(this.theme.surfaceBackgroundColor)
      .borderRadius(this.fontSize * 0.5)
      .margin({ left: this.fontSize * 1, right: this.fontSize * 1 });

      Text(this.t('答题详情', 'Answer Details'))
        .fontSize(this.fontSize)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.theme.titleColor)
        .padding({ left: this.fontSize * 1, right: this.fontSize * 1 });

      List({ scroller: this.resultListScroller, initialIndex: this.resultListScrollIndex }) {
        ForEach(this.quizQuestions, (question: QuizQuestion, qIndex: number) => {
          ListItem() {
            Row({ space: this.fontSize * 0.5 }) {
              Text(`${qIndex + 1}.`)
                .fontSize(this.fontSize * 0.9)
                .fontColor(this.theme.mutedTextColor);

              Text(question.question)
                .fontSize(this.fontSize * 0.85)
                .fontColor(this.theme.textColor)
                .layoutWeight(1)
                .maxLines(2)
                .textOverflow({ overflow: TextOverflow.Ellipsis });

              Text(this.quizAnswers[qIndex]?.isCorrect ? '✓' : '✗')
                .fontSize(this.fontSize)
                .fontColor(this.quizAnswers[qIndex]?.isCorrect ? 0xff4caf50 : this.theme.dangerTextColor);
            }
            .width('100%')
            .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 0.5, bottom: this.fontSize * 0.5 });
          }
        }, (question: QuizQuestion, qIndex: number) => `result_${qIndex}`);
      }
      .layoutWeight(1)
      .divider({ strokeWidth: 1, color: this.theme.borderColor, startMargin: this.fontSize * 1, endMargin: this.fontSize * 1 })
      .onScrollIndex((start: number, _end: number) => {
        const previous: number = this.resultListScrollIndex;
        if (previous !== start) {
          if (this.isLandscape) {
            this.onLandscapeScrollDirection?.(start > previous ? 'up' : 'down');
          }
          this.resultListScrollIndex = start;
        }
      });

      Row({ space: this.fontSize * 1 }) {
        Text(this.t('返回', 'Back'))
          .fontSize(this.fontSize)
          .fontColor(this.theme.accentColor)
          .padding({ left: this.fontSize * 1.5, right: this.fontSize * 1.5, top: this.fontSize * 0.8, bottom: this.fontSize * 0.8 })
          .backgroundColor(this.theme.surfaceBackgroundColor)
          .border({ width: 1, color: this.theme.accentColor })
          .borderRadius(this.fontSize * 0.5)
          .onClick(() => this.onResetQuiz?.());

        if (this.quizAvailableCount > 0) {
          Text(this.t('再来一次', 'Try Again'))
            .fontSize(this.fontSize)
            .fontColor(0xffffffff)
            .padding({ left: this.fontSize * 1.5, right: this.fontSize * 1.5, top: this.fontSize * 0.8, bottom: this.fontSize * 0.8 })
            .backgroundColor(this.theme.accentColor)
            .borderRadius(this.fontSize * 0.5)
            .onClick(() => this.onStartQuiz?.(Math.min(this.quizQuestions.length, this.quizAvailableCount)));
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .padding({ left: this.fontSize * 1, right: this.fontSize * 1, bottom: this.fontSize * 1 });
    }
    .layoutWeight(1)
    .width('100%');
  }

  build() {
    Column({ space: this.fontSize * 0.6 }) {
      Text(this.t('测验', 'Quiz'))
        .fontSize(this.fontSize * 1.5)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.theme.accentColor)
        .padding({ left: this.fontSize * 1, right: this.fontSize * 1, top: this.fontSize * 1 });

      if (this.quizMode === 'idle') {
        this.QuizIdleView();
      } else if (this.quizMode === 'selecting') {
        this.QuizSelectingView();
      } else if (this.quizMode === 'answering') {
        this.QuizAnsweringView();
      } else if (this.quizMode === 'result') {
        this.QuizResultView();
      }
    }
    .height('100%')
    .width('100%')
    .backgroundColor(this.theme.pageBackgroundColor);
  }
}
