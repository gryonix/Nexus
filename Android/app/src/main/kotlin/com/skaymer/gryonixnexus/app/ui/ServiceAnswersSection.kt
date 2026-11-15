package com.skaymer.gryonixnexus.app.ui

import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.skaymer.gryonixnexus.R
import com.skaymer.gryonixnexus.app.configurator.ConfiguratorForm
import com.skaymer.gryonixnexus.app.configurator.ConfiguratorViewModel
import com.skaymer.gryonixnexus.app.configurator.ServiceQuestions
import com.skaymer.gryonixnexus.app.ui.design.GroupedSection
import com.skaymer.gryonixnexus.app.ui.design.ToggleRow

/** Answers an install needs before it may run */
@Composable
fun ServiceAnswersSection(model: ConfiguratorViewModel, form: ConfiguratorForm, questions: List<ServiceQuestions.Question>) {
    GroupedSection(
        header = stringResource(R.string.wizard_service_answers),
        note = stringResource(R.string.wizard_service_answers_footer),
    ) {
        questions.forEachIndexed { index, question ->
            ToggleRow(
                title = stringResource(questionTitle(question)),
                checked = ServiceQuestions.isAnswered(question, form.serviceSettings),
                onCheckedChange = { accepted ->
                    model.update {
                        it.copy(serviceSettings = ServiceQuestions.answering(question, it.serviceSettings, accepted))
                    }
                },
                showDivider = index != questions.lastIndex,
            )
        }
    }
}

private fun questionTitle(question: ServiceQuestions.Question): Int = when (question) {
    ServiceQuestions.Question.MINECRAFT_JAVA_EULA -> R.string.wizard_minecraft_java_eula
    ServiceQuestions.Question.MINECRAFT_BEDROCK_EULA -> R.string.wizard_minecraft_bedrock_eula
    ServiceQuestions.Question.MACHINE_AT_HOME, ServiceQuestions.Question.SPEAKER_AT_HOME -> R.string.wizard_machine_at_home
}
